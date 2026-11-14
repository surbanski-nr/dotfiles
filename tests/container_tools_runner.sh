#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck source=../scripts/setup-lib
source "$repo_dir/scripts/setup-lib"
# shellcheck source=tools/fixture.sh
source "$repo_dir/tests/tools/fixture.sh"
load_config "$repo_dir/tools.env"
load_config "$repo_dir/system.env"

health_home=$(mktemp -d)
tmux_socket=$health_home/login.socket
agent_pid=
bin=/opt/mise/shims
export PATH="$bin:/opt/nvim2/mason/bin:$repo_dir/scripts:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export DOTFILES_IGNORE_USER_BIN=1 PYTHONDONTWRITEBYTECODE=1 GIT_OPTIONAL_LOCKS=0
export XDG_CACHE_HOME=$health_home/.cache XDG_STATE_HOME=$health_home/.local/state
export NVIM2_BENCHMARK_RUNS=3
unset VIRTUAL_ENV KUBECTL_VERSION HELM_VERSION PYTHONHOME PYTHONPATH
unset MISE_KUBECTL_VERSION MISE_HELM_VERSION

cleanup_container_checks() {
  local status=$?

  trap - EXIT
  tmux -S "$tmux_socket" kill-server >/dev/null 2>&1 || true
  if [[ -n $agent_pid ]]; then
    kill "$agent_pid" >/dev/null 2>&1 || true
    wait "$agent_pid" 2>/dev/null || true
  fi
  cleanup_path "$health_home" || status=1
  exit "$status"
}
trap cleanup_container_checks EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
cd "$repo_dir"

printf 'container-tools: checking system runtime commands\n'
for command_name in "${SYSTEM_RUNTIME_COMMANDS[@]}"; do
  require_command "$command_name"
done

health_stage 'locked mise installations' mise install --dry-run-code --locked
health_stage 'runtime account' test "$(id -u devcontainer)" = "$(id -u)"
health_stage 'runtime UID' test "$(id -u)" = "${DOTFILES_UID:-1000}"
health_stage 'runtime GID' test "$(id -g)" = "${DOTFILES_GID:-1000}"
runtime_groups=" $(id -G) "
if [[ ${DOTFILES_GID:-1000} != 0 &&
  ${DOTFILES_DOCKER_GID:-0} != 0 &&
  $runtime_groups == *' 0 '* ]]; then
  report_error 'runtime retained the root group without requiring it'
  exit 1
fi
for directory in \
  "$HOME" \
  "$HOME/.local/state/nvim2" \
  "$HOME/.local/share/tmux/resurrect" \
  /opt/nvim2 \
  /opt/tmux/plugins; do
  write_probe=$directory/.write-check.$$
  health_stage "$directory write access" mkdir "$write_probe"
  rmdir "$write_probe"
done
go_config_probe=$XDG_CONFIG_HOME/go/.env-check.$$
health_stage 'Go user configuration' env GOENV="$go_config_probe" \
  timeout --kill-after=5s 30s go env -w GOPRIVATE=example.invalid
rm -f -- "$go_config_probe"
health_stage 'SSH account lookup' bash -c 'ssh -TG example.invalid >/dev/null'
health_stage 'terminal cursor addressing' timeout --kill-after=2s 5s \
  sh -c 'tput cup 0 0 >/dev/null'
health_stage 'Docker daemon access' timeout --kill-after=5s 30s \
  docker info --format '{{.ServerVersion}}'
health_stage 'Bash history' timeout --kill-after=5s 180s bash tests/bash_history_test.sh

for tool in rg fzf zoxide uv terraform kubectx kubens yq task; do
  # shellcheck disable=SC1090
  source "$repo_dir/tests/tools/$tool.sh"
  health_stage "$tool" "health_$tool" "$bin" "$health_home"
done

version_args=()
# Image selection belongs to mise; version arguments are shared with host tools.
for command_name in "${!TOOL_CHECKS[@]}"; do
  if ! command -v "$command_name" >/dev/null; then
    continue
  fi
  arguments=${TOOL_CHECKS[$command_name]#*|}
  read -r -a version_args <<<"${arguments:---version}"
  health_stage "$command_name version" timeout --kill-after=5s 30s \
    "$command_name" "${version_args[@]}"
done
for command_name in "${!SYSTEM_PROBES[@]}"; do
  read -r -a version_args <<<"${SYSTEM_PROBES[$command_name]}"
  health_stage "$command_name version" timeout --kill-after=5s 30s \
    "${version_args[@]}"
done

for command_name in az aws claude codex copilot; do
  health_stage "$command_name version" timeout --kill-after=5s 30s \
    "$command_name" --version
done

for tool in kubectl helm; do
  # shellcheck disable=SC1090
  source "$repo_dir/tests/tools/$tool.sh"
  versions=$(mise ls --current "$tool" --json | jq -r '.[] | .version')
  arguments=${TOOL_CHECKS[$tool]#*|}
  read -r -a version_args <<<"$arguments"
  while IFS= read -r version; do
    (
      export "MISE_${tool^^}_VERSION=$version"
      output=$(timeout --kill-after=5s 30s "$bin/$tool" "${version_args[@]}")
      if [[ $output != *"$version"* ]]; then
        report_error "$tool $version selected an unexpected version: $output"
        exit 1
      fi
      health_stage "$tool $version" "health_$tool" "$bin" "$health_home"
    )
  done <<<"$versions"

  (
    cd "$health_home"
    export XDG_CONFIG_HOME=$health_home/.config
    export MISE_DATA_DIR=$health_home/.local/share/mise
    default_output=$("$bin/$tool" "${version_args[@]}")
    version=$(mise ls --installed "$tool" --json | jq -r '.[0].version')

    health_stage "$tool global selection" timeout --kill-after=5s 60s \
      mise use --global "$tool@$version"
    output=$("$bin/$tool" "${version_args[@]}")
    if [[ $output != *"$version"* ]]; then
      report_error "$tool global selection used an unexpected version: $output"
      exit 1
    fi

    health_stage "$tool restore image default" timeout --kill-after=5s 60s \
      mise use --global --remove "$tool"
    output=$("$bin/$tool" "${version_args[@]}")
    if [[ $output != "$default_output" ]]; then
      report_error "$tool did not restore the image default: $output"
      exit 1
    fi
  )
done

# shellcheck source=tools/k9s.sh
source "$repo_dir/tests/tools/k9s.sh"
yamllint=$(type -P yamllint || true)
health_stage k9s health_k9s "$bin" "$health_home" "$repo_dir/k9s/.config/k9s" "$yamllint"

for venv in /opt/nvim2/mason/packages/*/venv; do
  [[ -f $venv/pyvenv.cfg ]] || continue
  health_stage "${venv%/venv} Python dependencies" \
    env -u PYTHONHOME -u PYTHONPATH PIP_CONFIG_FILE=/dev/null \
    timeout --kill-after=5s 120s "$venv/bin/python" -I -B -m pip check
done

health_stage 'Neovim functional checks' timeout --kill-after=30s 1200s \
  bash nvim2/.config/nvim2/tests/check_runner.sh

# shellcheck source=tools/tmux.sh
source "$repo_dir/tests/tools/tmux.sh"
plugins=()
for plugin in /opt/tmux/plugins/tmux-*; do
  [[ -d $plugin ]] || continue
  plugins+=("${plugin##*/}")
done
health_stage tmux health_tmux "$(type -P tmux)" "$health_home" \
  "$repo_dir/tmux/.tmux.conf" /opt/tmux/plugins "${plugins[@]}"

printf 'container-tools: checking shared SSH agent and Neovim from tmux login Bash\n'
# The test owns this agent and key; it never uses the host's identities.
export SSH_AUTH_SOCK=$health_home/ssh-agent.socket
unset SSH_AGENT_PID
ssh-agent -D -a "$SSH_AUTH_SOCK" >"$health_home/ssh-agent.log" 2>&1 &
agent_pid=$!
# shellcheck disable=SC2016
health_stage 'SSH agent startup' timeout --kill-after=2s 10s bash -c '
  until [[ -S $SSH_AUTH_SOCK ]]; do
    sleep 0.05
  done
'
health_stage 'empty SSH agent in login Bash' timeout --kill-after=2s 15s \
  bash --login -ic 'ssh-add -l >/dev/null 2>&1; [[ $? -eq 1 ]]'
ssh-keygen -q -t ed25519 -N '' -C container-check -f "$health_home/ssh-key"
tmux -S "$tmux_socket" new-session -d -s check
# shellcheck disable=SC2016
health_stage 'add SSH key from login Bash' timeout --kill-after=2s 15s \
  bash --login -ic 'ssh-add "$1"' agent-check "$health_home/ssh-key"
# shellcheck disable=SC2016
health_stage 'shared SSH key after Bash reload' timeout --kill-after=2s 15s \
  bash --login -ic 'source "$HOME/.bashrc"; ssh-add -T "$1"' \
    agent-check "$health_home/ssh-key.pub"
printf -v command 'ssh-add -T %q && nvim --version > %q' \
  "$health_home/ssh-key.pub" "$health_home/tmux-nvim-version"
tmux -S "$tmux_socket" send-keys -t check "$command" Enter
deadline=$((SECONDS + 15))
until [[ -s $health_home/tmux-nvim-version ]]; do
  if ((SECONDS >= deadline)); then
    tmux -S "$tmux_socket" capture-pane -p -t check >&2
    exit 1
  fi
  sleep 0.2
done
test "$(sed -n '1p' "$health_home/tmux-nvim-version")" = "$(nvim --version | sed -n '1p')"
printf 'container-tools: all checks passed\n'
