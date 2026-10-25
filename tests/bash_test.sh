#!/usr/bin/env bash

set -euo pipefail
unset DOTFILES_IGNORE_USER_BIN

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
command_fixture=$repo_dir/tests/fixtures/bash/command
scenario_fixture=$repo_dir/tests/fixtures/bash/scenario
test_root=$(mktemp -d)
original_path=$PATH

cleanup() {
  local status=$?
  PATH=$original_path
  find "$test_root" -depth -delete
  exit "$status"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local value=$1
  local expected=$2
  [[ $value == *"$expected"* ]] || fail "expected output to contain: $expected"
}

link_command() {
  ln -s "$command_fixture" "$test_root/bin/$1"
}

run_scenario() {
  local scenario=$1
  shift
  env TEST_REPO_DIR="$repo_dir" TEST_SCENARIO="$scenario" "$@" \
    "$scenario_fixture"
}

mkdir -p "$test_root/bin"
ln -s "$(command -v bash)" "$test_root/bin/bash"
ln -s "$(command -v grep)" "$test_root/bin/grep"
for command_name in git tmux fzf less mc; do
  link_command "$command_name"
done

set +e
check_output=$(
  env -i HOME="$test_root" PATH="$test_root/bin" \
    TEST_REPO_DIR="$repo_dir" TEST_SCENARIO=check-tools "$scenario_fixture" 2>&1
)
check_status=$?
set -e
[[ $check_status -eq 1 ]] || fail 'dotfiles-check accepted a missing required command'
assert_contains "$check_output" 'MISSING nvim'
assert_contains "$check_output" 'MISSING zoxide'

link_command nvim
for command_name in node python rg; do
  link_command "$command_name"
done
wrapper_output=$(
  run_scenario check-mc-wrapper \
    env HOME="$test_root" DOTFILES="$test_root/no-manifest" PATH="$test_root/bin"
)
assert_contains "$wrapper_output" 'mc: '
assert_contains "$wrapper_output" '(shell wrapper: alias)'

editor_output=$(
  TEST_COMMAND_MODE=editor run_scenario editor \
    env HOME="$test_root" PATH="$test_root/bin"
)
[[ $editor_output == 'app=nvim2 argc=1 first=file with space' ]] ||
  fail 'v did not preserve the Nvim2 profile or argument quoting'

python_home=$test_root/python-home
python_xdg=$test_root/'python config'
python_manifest=$test_root/python-manifest
mkdir -p "$python_home/bin" "$python_xdg/uv" "$python_home/project" "$python_manifest/scripts"
cp "$repo_dir/tools.env" "$python_manifest/tools.env"
printf 'TOOL_RELEASES[python]=%q\n' \
  $'\n3.9.7|https://example.invalid/python-3.9.7.tar.gz|0000000000000000000000000000000000000000000000000000000000000000\n' \
  >>"$python_manifest/tools.env"
ln -s "$repo_dir/scripts/setup-lib" "$python_manifest/scripts/setup-lib"
for command_name in bash grep timeout; do
  ln -s "$(command -v "$command_name")" "$python_home/bin/$command_name"
done
for command_name in git nvim tmux less mc node python rg uv; do
  ln -s "$command_fixture" "$python_home/bin/$command_name"
done
printf '3.9.7\n' >"$python_xdg/uv/.python-version"
printf '3.10.0\n' >"$python_home/project/.python-version"
python_output=$(
  cd "$python_home/project"
  TEST_COMMAND_MODE=versions run_scenario check-tools \
    env HOME="$python_home" XDG_CONFIG_HOME="$python_xdg" DOTFILES="$python_manifest" \
    PATH="$python_home/bin"
)
assert_contains "$python_output" 'OK      uv Python'
printf '3.11.0\n' >"$python_xdg/uv/.python-version"
if TEST_COMMAND_MODE=versions run_scenario check-tools \
  env HOME="$python_home" XDG_CONFIG_HOME="$python_xdg" DOTFILES="$python_manifest" \
  PATH="$python_home/bin" >"$test_root/python-mismatch.log"; then
  fail 'version diagnostics accepted the wrong global Python'
fi
assert_contains "$(<"$test_root/python-mismatch.log")" 'MISMATCH uv Python'

set +e
missing_output=$(
  run_scenario missing-kubectl \
    env HOME="$test_root" PATH="$test_root/bin" 2>&1
)
missing_status=$?
set -e
[[ $missing_status -eq 127 ]] || fail 'missing kubectl did not return 127'
[[ $missing_output == 'dotfiles: kl requires kubectl' ]] ||
  fail 'missing dependency message was noisy or unclear'

link_command kubectl
filtered=$(
  TEST_COMMAND_MODE=filter run_scenario filter-pods \
    env HOME="$test_root" PATH="$test_root/bin"
)
assert_contains "$filtered" 'pod-a=-v'

set +e
TEST_COMMAND_MODE=failure run_scenario failed-pod-list \
  env HOME="$test_root" PATH="$test_root/bin" >/dev/null 2>&1
kpl_status=$?
set -e
[[ $kpl_status -eq 42 ]] || fail 'kpl hid kubectl get pods failure'

link_command bat
set +e
TEST_COMMAND_MODE=failure run_scenario failed-log-pipeline \
  env HOME="$test_root" PATH="$test_root/bin" >/dev/null 2>&1
kl_status=$?
set -e
[[ $kl_status -eq 42 ]] || fail 'kl hid the left side of its pipeline'

mkdir -p "$test_root/logs"
(
  cd "$test_root/logs"
  TEST_COMMAND_MODE=logs run_scenario write-pod-logs \
    env HOME="$test_root" PATH="$test_root/bin:$original_path"
  [[ $(<api-1.log) == 'logs for api-1' ]]
  [[ ! -e worker-1.log ]]
) || fail 'kpl did not write only successful matching pod logs'

reload_home=$test_root/reload-home
mkdir -p "$reload_home"
ln -s "$repo_dir/bash/.bash_aliases" "$reload_home/.bash_aliases"
link_command zoxide
reload_output=$(
  timeout 15 env HOME="$reload_home" PATH="$test_root/bin:$original_path" \
    TERM=xterm-256color TEST_REPO_DIR="$repo_dir" TEST_SCENARIO=prompt-history \
    TEST_COMMAND_MODE=reload TEST_PROMPT_LOG="$test_root/prompts.log" \
    bash --noprofile --norc -i "$scenario_fixture" 2>&1
)
for origin in first second; do
  [[ $(grep -c "command from $origin shell" <<<"$reload_output") -eq 1 ]] ||
    fail "history did not retain exactly one command from the $origin shell"
done
[[ $(grep -cx 'command from first shell' "$reload_home/.histfile") -eq 1 ]] ||
  fail 'prompt did not append the local command to shared history'
for hook in user zoxide; do
  [[ $(grep -cx "$hook" "$test_root/prompts.log") -eq 2 ]] ||
    fail "$hook prompt ran more than once per prompt after reload"
done

shared_history_home=$test_root/shared-history-home
mkdir -p "$shared_history_home"
shared_history_output=$(
  timeout 15s env -i HOME="$shared_history_home" PATH="$test_root/bin:$original_path" \
    TERM=xterm-256color TEST_REPO_DIR="$repo_dir" TEST_SCENARIO=shared-history \
    bash --noprofile --norc -i "$scenario_fixture" 2>&1
)
for origin in first second; do
  for round in 1 2; do
    command_line="command from $origin shell $round"
    [[ $(grep -c "$command_line" <<<"$shared_history_output") -eq 1 ]] ||
      fail "shared history did not import exactly one $origin-shell command in round $round"
    [[ $(grep -cx "$command_line" "$shared_history_home/.histfile") -eq 1 ]] ||
      fail "shared history duplicated or lost the $origin-shell command in round $round"
  done
done

array_history_home=$test_root/array-history-home
array_prompt_log=$test_root/array-prompts.log
mkdir -p "$array_history_home"
array_history_output=$(
  timeout 15s env -i HOME="$array_history_home" PATH="$test_root/bin:$original_path" \
    TERM=xterm-256color TEST_REPO_DIR="$repo_dir" TEST_SCENARIO=prompt-history-array \
    TEST_PROMPT_LOG="$array_prompt_log" \
    bash --noprofile --norc -i "$scenario_fixture" 2>&1
)
assert_contains "$array_history_output" 'history_hooks=1'
for hook in user other-user; do
  [[ $(grep -cx "$hook" "$array_prompt_log") -eq 2 ]] ||
    fail "$hook array prompt hook was lost or duplicated after reload"
done
[[ $(grep -cx 'command with array hooks' "$array_history_home/.histfile") -eq 1 ]] ||
  fail 'array prompt hooks duplicated or lost the saved command'

failed_history_home=$test_root/failed-history-home
mkdir -p "$failed_history_home"
failed_history_output=$(
  timeout 15s env -i HOME="$failed_history_home" PATH="$test_root/bin:$original_path" \
    TERM=xterm-256color TEST_REPO_DIR="$repo_dir" TEST_SCENARIO=history-save-failure \
    bash --noprofile --norc -i "$scenario_fixture" 2>&1
)
[[ $(grep -c 'command awaiting successful save' <<<"$failed_history_output") -eq 3 ]] ||
  fail 'an unsuccessful or disabled history save discarded the pending command'
[[ $(grep -cx 'command awaiting successful save' "$failed_history_home/.histfile") -eq 1 ]] ||
  fail 'retrying history synchronization duplicated or lost the pending command'

broken_output=$(
  timeout 15 env HOME="$reload_home" PATH="$test_root/bin:$original_path" \
    TERM=xterm-256color TEST_REPO_DIR="$repo_dir" TEST_SCENARIO=broken-integration \
    bash --noprofile --norc -i "$scenario_fixture" 2>&1
)
assert_contains "$broken_output" 'dotfiles: zoxide initialization failed'
[[ $broken_output != *'command not found'* ]] ||
  fail 'broken integration emitted raw shell errors'

invalid_output=$(
  timeout 15 env HOME="$reload_home" PATH="$test_root/bin:$original_path" \
    TERM=xterm-256color TEST_REPO_DIR="$repo_dir" TEST_SCENARIO=invalid-integration \
    bash --noprofile --norc -i "$scenario_fixture" 2>&1
)
assert_contains "$invalid_output" 'dotfiles: zoxide returned invalid shell initialization'
assert_contains "$invalid_output" 'continued=yes'
[[ $invalid_output != *'syntax error'* ]] ||
  fail 'invalid integration emitted raw shell errors'

agent_home=$test_root/agent-home
agent_bin=$test_root/agent-bin
agent_log=$test_root/agent.log
mkdir -p "$agent_home/.ssh" "$agent_bin"
printf 'invalid key\n' >"$agent_home/.ssh/github"
chmod 600 "$agent_home/.ssh/github"
printf ':\n' >"$agent_home/.bashrc"
ln -s "$command_fixture" "$agent_bin/ssh-agent"
ln -s "$command_fixture" "$agent_bin/ssh-add"

profile_output=$(
  env -i HOME="$agent_home" PATH="$agent_bin:/usr/bin:/bin" \
    TEST_AGENT_LOG="$agent_log" TEST_COMMAND_MODE=agent \
    TEST_REPO_DIR="$repo_dir" TEST_SCENARIO=failed-agent-key \
    "$scenario_fixture" 2>&1
)
assert_contains "$profile_output" 'profile_status=0 sock=unset pid=unset'
[[ ! -e $agent_log ]] || fail 'login profile started an ssh-agent'

stale_output=$(
  env -i HOME="$agent_home" PATH=/usr/bin:/bin SSH_AUTH_SOCK=/missing/agent.sock \
    TEST_REPO_DIR="$repo_dir" TEST_SCENARIO=stale-agent-socket \
    "$scenario_fixture" 2>&1
)
assert_contains "$stale_output" 'dotfiles: SSH_AUTH_SOCK is not a socket: /missing/agent.sock'
assert_contains "$stale_output" 'stale_status=0 sock=unset'

shared_home=$test_root/shared-agent-home
shared_runtime=$test_root/shared-agent-runtime
shared_bin=$test_root/shared-agent-bin
shared_log=$test_root/shared-agent.log
shared_state=$test_root/shared-agent.state
mkdir -p "$shared_home/.config/systemd/user" "$shared_runtime" "$shared_bin"
printf '[Service]\n' >"$shared_home/.config/systemd/user/dotfiles-ssh-agent.service"
ln -s "$command_fixture" "$shared_bin/ssh-add"
ln -s "$command_fixture" "$shared_bin/systemctl"
shared_output=$(
  env -i HOME="$shared_home" PATH="$shared_bin:/usr/bin:/bin" \
    XDG_RUNTIME_DIR="$shared_runtime" TERM=xterm-256color \
    TEST_AGENT_LOG="$shared_log" TEST_AGENT_STATE="$shared_state" \
    TEST_COMMAND_MODE=shared-agent TEST_REPO_DIR="$repo_dir" \
    TEST_SCENARIO=shared-agent \
    bash --noprofile --norc -i "$scenario_fixture" 2>&1
)
assert_contains "$shared_output" "shared_sock=$shared_runtime/dotfiles-ssh-agent.socket pid=unset"
[[ $(grep -cx 'systemctl --user start dotfiles-ssh-agent.service' "$shared_log") -eq 1 ]] ||
  fail 'reloading Bash did not reuse one shared ssh-agent service'
second_shell_output=$(
  env -i HOME="$shared_home" PATH="$shared_bin:/usr/bin:/bin" \
    XDG_RUNTIME_DIR="$shared_runtime" TERM=xterm-256color \
    TEST_AGENT_LOG="$shared_log" TEST_AGENT_STATE="$shared_state" \
    TEST_AGENT_STATUS=0 TEST_COMMAND_MODE=shared-agent TEST_REPO_DIR="$repo_dir" \
    TEST_SCENARIO=shared-agent \
    bash --noprofile --norc -i "$scenario_fixture" 2>&1
)
assert_contains "$second_shell_output" \
  "shared_sock=$shared_runtime/dotfiles-ssh-agent.socket pid=unset"
[[ $(grep -cx 'systemctl --user start dotfiles-ssh-agent.service' "$shared_log") -eq 1 ]] ||
  fail 'a second shell started another ssh-agent service'

inherited_log=$test_root/inherited-agent.log
inherited_socket=$test_root/inherited-agent.socket
inherited_state=$test_root/inherited-agent.state
inherited_output=$(
  env -i HOME="$shared_home" PATH="$shared_bin:/usr/bin:/bin" \
    XDG_RUNTIME_DIR="$shared_runtime" SSH_AUTH_SOCK="$inherited_socket" \
    SSH_AGENT_PID=4242 TERM=xterm-256color TEST_AGENT_LOG="$inherited_log" \
    TEST_AGENT_STATE="$inherited_state" \
    TEST_FORWARDED_SOCKET="$inherited_socket" TEST_COMMAND_MODE=shared-agent \
    TEST_REPO_DIR="$repo_dir" TEST_SCENARIO=shared-agent \
    bash --noprofile --norc -i "$scenario_fixture" 2>&1
)
assert_contains "$inherited_output" \
  "shared_sock=$inherited_socket pid=4242"
if grep -q '^systemctl ' "$inherited_log"; then
  fail 'a working inherited agent was replaced with the shared agent'
fi

stale_inherited_log=$test_root/stale-inherited-agent.log
stale_inherited_output=$(
  env -i HOME="$shared_home" PATH="$shared_bin:/usr/bin:/bin" \
    XDG_RUNTIME_DIR="$shared_runtime" SSH_AUTH_SOCK=/missing/agent.sock \
    SSH_AGENT_PID=4242 TERM=xterm-256color TEST_AGENT_LOG="$stale_inherited_log" \
    TEST_AGENT_STATE="$shared_state" TEST_COMMAND_MODE=shared-agent \
    TEST_REPO_DIR="$repo_dir" TEST_SCENARIO=shared-agent \
    bash --noprofile --norc -i "$scenario_fixture" 2>&1
)
assert_contains "$stale_inherited_output" \
  "shared_sock=$shared_runtime/dotfiles-ssh-agent.socket pid=unset"
if grep -q '^systemctl ' "$stale_inherited_log"; then
  fail 'a stale inherited socket prevented reuse of the running shared agent'
fi

failed_agent_output=$(
  env -i HOME="$shared_home" PATH="$shared_bin:/usr/bin:/bin" \
    XDG_RUNTIME_DIR="$shared_runtime" TERM=xterm-256color \
    TEST_AGENT_LOG="$test_root/failed-agent.log" TEST_AGENT_STATE="$test_root/failed-agent.state" \
    TEST_AGENT_START_FAIL=1 TEST_COMMAND_MODE=shared-agent TEST_REPO_DIR="$repo_dir" \
    TEST_SCENARIO=shared-agent \
    bash --noprofile --norc -i "$scenario_fixture" 2>&1
)
assert_contains "$failed_agent_output" 'dotfiles: failed to start the shared ssh-agent service'
assert_contains "$failed_agent_output" 'shared_sock=unset pid=unset'

link_command vi
link_command vim
editor_log=$test_root/editors.log
independent_output=$(
  TEST_COMMAND_MODE=independent TEST_EDITOR_LOG="$editor_log" \
    run_scenario independent-editors \
    env HOME="$reload_home" PATH="$test_root/bin:$original_path" TERM=xterm-256color \
    bash --noprofile --norc -i
)
assert_contains "$independent_output" 'cat=file vi=function vim=alias v=function'
assert_contains "$(<"$editor_log")" 'vi:first'
assert_contains "$(<"$editor_log")" 'vim:second'

git_home=$test_root/git-home
git_bin=$test_root/git-bin
git_editor_log=$test_root/git-editor.log
mkdir -p "$git_home" "$git_bin"
cp "$repo_dir/git/.gitconfig" "$git_home/.gitconfig"
cp "$repo_dir/tests/fixtures/bash/git-editor" "$git_bin/vi"
chmod 0755 "$git_bin/vi"
ln -s "$(PATH="$original_path" command -v git)" "$git_bin/git"
timeout 15s env -u GIT_EDITOR -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT \
  HOME="$git_home" PATH="$git_bin:/usr/bin:/bin" TERM=xterm-256color \
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$git_home/.gitconfig" \
  TEST_GIT_EDITOR_LOG="$git_editor_log" TEST_REPO_DIR="$repo_dir" \
  TEST_SCENARIO=git-editor bash --noprofile --norc -i "$scenario_fixture"
[[ $(<"$git_editor_log") == 'editor=vi visual=vi' ]] ||
  fail 'Git commit or shell editor defaults did not use system vi'

checkout_with_spaces="$test_root/checkout with spaces"
mkdir -p "$checkout_with_spaces/scripts"
custom_output=$(
  run_scenario custom-dotfiles \
    env HOME="$reload_home" DOTFILES="$checkout_with_spaces" \
    PATH="$test_root/bin:$original_path" TERM=xterm-256color \
    bash --noprofile --norc -i
)
assert_contains "$custom_output" "dotfiles=$checkout_with_spaces pwd=$checkout_with_spaces"

transition_home="$test_root/transition home"
transition_connected="$test_root/connected checkout/dotfiles"
transition_a="$transition_home/dotfiles-releases/dotfiles-aaaaaaaaaaaa"
transition_b="$transition_home/dotfiles-releases/dotfiles-bbbbbbbbbbbb"
mkdir -p "$transition_home/.asdf/shims"
printf '#!/usr/bin/env bash\nprintf "asdf\\n"\n' >"$transition_home/.asdf/shims/asdf-only-tool"
chmod 0755 "$transition_home/.asdf/shims/asdf-only-tool"
for root in "$transition_connected" "$transition_a/dotfiles" "$transition_b/dotfiles"; do
  mkdir -p "$root/bash" "$root/scripts"
  cp "$repo_dir/bash/.bashrc" "$repo_dir/bash/.bash_history_lib" "$root/bash/"
  cp "$repo_dir/scripts/bash-history-archive" "$root/scripts/"
done
printf 'RELEASE_ID=dotfiles-aaaaaaaaaaaa\n' >"$transition_a/release.env"
printf 'RELEASE_ID=dotfiles-bbbbbbbbbbbb\n' >"$transition_b/release.env"
for release in "$transition_a" "$transition_b"; do
  mkdir -p "$release/bin"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" %q\n' "release-${release: -1}" \
    >"$release/bin/release-command"
  cp "$release/bin/release-command" "$release/dotfiles/scripts/config-marker"
  chmod 0755 "$release/bin/release-command" "$release/dotfiles/scripts/config-marker"
done
for provider in bin share/nvim2/mason/bin share/nvim2/mason/packages/ansible-lint/venv/bin dotfiles/scripts; do
  mkdir -p "$transition_a/$provider"
done
cp "$transition_a/bin/release-command" "$transition_a/bin/removed-release-command"
cp "$transition_a/bin/release-command" "$transition_a/share/nvim2/mason/bin/removed-mason-command"
cp "$transition_a/bin/release-command" "$transition_a/share/nvim2/mason/packages/ansible-lint/venv/bin/removed-venv-command"
cp "$transition_a/bin/release-command" "$transition_a/dotfiles/scripts/removed-script-command"
ln -s "${transition_a##*/}" "$transition_home/dotfiles-releases/current"
ln -s dotfiles-releases/current/dotfiles/bash/.bashrc "$transition_home/.bashrc"
transition_output=$(
  run_scenario release-switch \
    env HOME="$transition_home" PATH="$test_root/bin:$original_path" \
    TERM=xterm-256color TEST_RELEASE_A="$transition_a" TEST_RELEASE_B="$transition_b" \
    bash --noprofile --norc -i
)
assert_contains "$transition_output" 'before=release-a config=release-a'
assert_contains "$transition_output" \
  "after=release-b config=release-b asdf=$transition_home/.asdf/shims/asdf-only-tool"
assert_contains "$transition_output" 'reselected=release-a'
[[ -x $transition_a/bin/removed-release-command &&
  -x $transition_a/share/nvim2/mason/bin/removed-mason-command &&
  -x $transition_a/share/nvim2/mason/packages/ansible-lint/venv/bin/removed-venv-command &&
  -x $transition_a/dotfiles/scripts/removed-script-command ]] ||
  fail 'switching releases removed retained tools instead of cleaning PATH'

custom_root="$test_root/custom root"
second_custom_root="$test_root/second custom root"
mkdir -p "$custom_root/scripts" "$second_custom_root/scripts"
override_output=$(
  run_scenario root-override \
    env HOME="$transition_home" PATH="$test_root/bin:$original_path" \
    TERM=xterm-256color TEST_CONNECTED_ROOT="$transition_connected" \
    TEST_RELEASE_A="$transition_a" TEST_RELEASE_B="$transition_b" \
    TEST_CUSTOM_ROOT="$custom_root" TEST_SECOND_CUSTOM_ROOT="$second_custom_root" \
    bash --noprofile --norc -i
)
assert_contains "$override_output" "override-before=$custom_root:unset"
assert_contains "$override_output" "override-during=$second_custom_root:unset"
assert_contains "$override_output" "legacy-before-reset=$transition_a/dotfiles"
assert_contains "$override_output" "legacy-after-reset=$transition_connected"

launcher_environment_output=$(
  run_scenario launcher-environment \
    env HOME="$transition_home" PATH="$test_root/bin:$original_path" \
    TERM=xterm-256color \
    XDG_CONFIG_HOME="$transition_a/config" XDG_DATA_HOME="$transition_a/share" \
    _ZO_DATA_DIR="$test_root/user data/zoxide" \
    DOTFILES_LAUNCHER_XDG_CONFIG_HOME_SET=1 \
    DOTFILES_LAUNCHER_XDG_CONFIG_HOME="$test_root/user config" \
    DOTFILES_LAUNCHER_XDG_DATA_HOME_SET=1 \
    DOTFILES_LAUNCHER_XDG_DATA_HOME="$test_root/user data" \
    DOTFILES_LAUNCHER_ZO_DATA_DIR_SET=0 \
    GOTOOLCHAIN=local \
    DOTFILES_LAUNCHER_GOROOT_SET=1 DOTFILES_LAUNCHER_GOROOT="$test_root/project SDK" \
    DOTFILES_LAUNCHER_GOTOOLCHAIN_SET=1 DOTFILES_LAUNCHER_GOTOOLCHAIN=auto \
    bash --noprofile --norc -i
)
assert_contains "$launcher_environment_output" \
  "xdg-config=$test_root/user config xdg-data=$test_root/user data zoxide=unset markers="
assert_contains "$launcher_environment_output" "go-root=$test_root/project SDK go-toolchain=auto go-markers="

launcher_unset_output=$(
  run_scenario launcher-environment \
    env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u _ZO_DATA_DIR \
    HOME="$transition_home" PATH="$test_root/bin:$original_path" \
    TERM=xterm-256color \
    DOTFILES_LAUNCHER_XDG_CONFIG_HOME_SET=0 \
    DOTFILES_LAUNCHER_XDG_DATA_HOME_SET=0 \
    DOTFILES_LAUNCHER_ZO_DATA_DIR_SET=0 \
    GOROOT="$transition_a/tools/go" GOTOOLCHAIN=local \
    DOTFILES_LAUNCHER_GOROOT_SET=0 DOTFILES_LAUNCHER_GOTOOLCHAIN_SET=0 \
    bash --noprofile --norc -i
)
assert_contains "$launcher_unset_output" \
  'xdg-config=unset xdg-data=unset zoxide=unset markers='
assert_contains "$launcher_unset_output" 'go-root=unset go-toolchain=unset go-markers='

path_home=$test_root/path-home
mkdir -p "$path_home/.venv/bin" "$path_home/.asdf/shims" "$path_home/bin"
ln -s "$command_fixture" "$path_home/.venv/bin/python"
ln -s "$command_fixture" "$path_home/.asdf/shims/terraform"
ln -s "$command_fixture" "$path_home/bin/terraform"
path_output=$(
  run_scenario path-order \
    env HOME="$path_home" VIRTUAL_ENV="$path_home/.venv" \
    PATH="$path_home/bin:$original_path" TERM=xterm-256color \
    bash --noprofile --norc -i
)
assert_contains "$path_output" "python=$path_home/.venv/bin/python"
assert_contains "$path_output" "terraform=$path_home/bin/terraform"
path_line=$(grep '^path=' <<<"$path_output")
[[ ${path_line#path=} == "$path_home/.venv/bin:"* ]] ||
  fail 'active virtual environment lost PATH precedence'

for setup_mode in connected repo-with-release offline custom-store; do
  override_home="$test_root/$setup_mode override home"
  override_store=$override_home/dotfiles-releases
  [[ $setup_mode != custom-store ]] || override_store="$override_home/releases with spaces"
  for provider in bin .asdf/shims .krew/bin .local/bin \
    .local/share/nvim2/mason/bin 'project venv/bin'; do
    mkdir -p "$override_home/$provider"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" %q\n' "$provider" \
      >"$override_home/$provider/path-probe"
    chmod 0755 "$override_home/$provider/path-probe"
  done
  cp "$override_home/bin/path-probe" "$override_home/bin/unique-user-tool"
  cp "$override_home/.asdf/shims/path-probe" "$override_home/.asdf/shims/asdf-only-tool"
  printf '#!/usr/bin/env bash\nprintf "cwd\\n"\n' >"$test_root/cwd-only"
  chmod 0755 "$test_root/cwd-only"
  override_bashrc=$repo_dir/bash/.bashrc
  fallback=.asdf/shims
  if [[ $setup_mode != connected ]]; then
    override_release=$override_store/dotfiles-cccccccccccc
    mkdir -p "$override_release/dotfiles/bash" "$override_release/dotfiles/scripts" "$override_release/bin"
    cp "$override_bashrc" "$repo_dir/bash/.bash_history_lib" "$override_release/dotfiles/bash/"
    cp "$repo_dir/scripts/bash-history-archive" "$override_release/dotfiles/scripts/"
    printf 'RELEASE_ID=dotfiles-cccccccccccc\n' >"$override_release/release.env"
    printf '#!/usr/bin/env bash\nprintf "release\\n"\n' >"$override_release/bin/path-probe"
    chmod 0755 "$override_release/bin/path-probe"
    ln -s dotfiles-cccccccccccc "$override_store/current"
    if [[ $setup_mode != repo-with-release ]]; then
      override_bashrc=$override_release/dotfiles/bash/.bashrc
    fi
    fallback=release
  fi
  override_output=$(
    cd "$test_root"
    run_scenario user-bin \
      env -u DOTFILES_IGNORE_USER_BIN HOME="$override_home" TEST_BASHRC="$override_bashrc" \
      DOTFILES_RELEASE_ROOT="$override_store" \
      PATH=":$override_home/bin:$test_root/bin::$original_path:$override_home/bin:" \
      TERM=xterm-256color bash --noprofile --norc -i
  )
  assert_contains "$override_output" 'override=bin unique=bin'
  assert_contains "$override_output" 'asdf-only=.asdf/shims'
  assert_contains "$override_output" 'venv=project venv/bin'
  if [[ $setup_mode == connected ]]; then
    [[ $override_output != *"$override_store/current/bin"* ]] ||
      fail 'missing release directory was added to PATH'
  else
    assert_contains "$override_output" "$override_store/current/bin"
  fi
  for phase in nonexecutable ignored removed regular-file; do
    assert_contains "$override_output" "$phase=$fallback"
  done
done

brew_home=$test_root/brew-home
brew_bin=$test_root/existing-homebrew/bin
brew_log=$test_root/brew.log
mkdir -p "$brew_home" "$brew_bin"
ln -s "$command_fixture" "$brew_bin/brew"
TEST_BREW_LOG="$brew_log" run_scenario reload \
  env HOME="$brew_home" PATH="$brew_bin:$test_root/bin:$original_path" \
  TERM=xterm-256color bash --noprofile --norc -i >/dev/null 2>&1
[[ ! -e $brew_log ]] || fail 'Bash startup invoked Homebrew'

fzf_output=$(
  TEST_COMMAND_MODE=fzf-init run_scenario fzf-init \
    env HOME="$reload_home" PATH="$test_root/bin:$original_path" TERM=xterm-256color \
    bash --noprofile --norc -i
)
assert_contains "$fzf_output" 'fzf-init=yes'

fzf_failure_output=$(
  TEST_COMMAND_MODE=broken-integration run_scenario fzf-failure \
    env HOME="$reload_home" PATH="$test_root/bin:$original_path" TERM=xterm-256color \
    bash --noprofile --norc -i 2>&1
)
assert_contains "$fzf_failure_output" 'dotfiles: fzf initialization failed'
assert_contains "$fzf_failure_output" 'continued=yes'

kube_completion_output=$(
  TEST_COMMAND_MODE=kube-completion run_scenario kube-completion \
    env HOME="$reload_home" PATH="$test_root/bin:$original_path" TERM=xterm-256color \
    bash --noprofile --norc -i
)
assert_contains "$kube_completion_output" 'complete -F __start_kubectl k'
assert_contains "$kube_completion_output" 'k-completion=fixture-pod'

stale_vz_output=$(
  run_scenario stale-vz \
    env HOME="$reload_home" PATH="$test_root/bin:$original_path"
)
[[ $stale_vz_output == 'editor=v stale=removed' ]] ||
  fail 'alias reload did not remove stale editor helpers while preserving v'

posh_log=$test_root/oh-my-posh.log
posh_state=$test_root/kubectl-prompt-disabled
ln -s "$command_fixture" "$test_root/bin/oh-my-posh"
ln -s "$repo_dir/oh-my-posh/.oh-my-posh.omp.json" \
  "$reload_home/.oh-my-posh.omp.json"
for terminal in dumb xterm-256color; do
  fallback_output=$(
    TEST_COMMAND_MODE=broken-integration run_scenario fallback-prompt \
      env HOME="$reload_home" PATH="$test_root/bin:$original_path" TERM="$terminal" \
      bash --noprofile --norc -i 2>&1
  )
  assert_contains "$fallback_output" 'dotfiles: Oh My Posh initialization failed'
  assert_contains "$fallback_output" "$(id -un)@"
  [[ $terminal != dumb || $fallback_output != *$'\e'* ]] ||
    fail 'fallback prompt emitted terminal escapes on a dumb terminal'
done

kube_init_output=$(
  TEST_COMMAND_MODE=kube-prompt TEST_POSH_LOG="$posh_log" \
    TEST_POSH_STATE="$posh_state" run_scenario kube-prompt-init \
    env HOME="$reload_home" PATH="$test_root/bin:$original_path" \
    TERM=xterm-256color bash --noprofile --norc -i
)
assert_contains "$kube_init_output" 'kube-default=disabled'
[[ $(grep -c '^init bash ' "$posh_log") -eq 1 ]] ||
  fail 'Oh My Posh was initialized more than once on Bash reload'
[[ $(grep -c '^toggle kubectl$' "$posh_log") -eq 1 ]] ||
  fail 'Kubernetes prompt default was not initialized exactly once'

kube_toggle_output=$(
  TEST_COMMAND_MODE=kube-prompt TEST_POSH_LOG="$posh_log" \
    TEST_POSH_STATE="$posh_state" run_scenario kube-prompt-toggle \
    env HOME="$reload_home" PATH="$test_root/bin:$original_path"
)
assert_contains "$kube_toggle_output" 'Kubernetes prompt enabled'
assert_contains "$kube_toggle_output" 'Kubernetes prompt disabled'
[[ $(grep -c '^get toggles$' "$posh_log") -eq 2 ]] ||
  fail 'kp did not inspect the native Oh My Posh toggle state'
[[ $(grep -c '^toggle kubectl$' "$posh_log") -eq 3 ]] ||
  fail 'kp did not toggle the Kubernetes segment twice'

printf 'Bash tests passed\n'
