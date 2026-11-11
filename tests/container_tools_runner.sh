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

printf 'container-tools: checking Neovim from tmux login Bash\n'
tmux -S "$tmux_socket" new-session -d -s check
printf -v command 'nvim --version > %q' "$health_home/tmux-nvim-version"
tmux -S "$tmux_socket" send-keys -t check "$command" Enter
deadline=$((SECONDS + 15))
until [[ -s $health_home/tmux-nvim-version ]]; do
  if (( SECONDS >= deadline )); then
    tmux -S "$tmux_socket" capture-pane -p -t check >&2
    exit 1
  fi
  sleep 0.2
done
test "$(sed -n '1p' "$health_home/tmux-nvim-version")" = "$(nvim --version | sed -n '1p')"
printf 'container-tools: all checks passed\n'
