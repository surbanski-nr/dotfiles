#!/usr/bin/env bash

set -euo pipefail

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
reload_output=$(
  timeout 15 env HOME="$reload_home" PATH="$test_root/bin:$original_path" \
    TERM=xterm-256color TEST_REPO_DIR="$repo_dir" TEST_SCENARIO=reload \
    bash --noprofile --norc -i "$scenario_fixture" 2>&1
)
[[ $(grep -o '_dotfiles_history_sync' <<<"$reload_output" | wc -l) -eq 1 ]] ||
  fail 'history prompt hook was duplicated on reload'
[[ $(grep -o '__zoxide_hook' <<<"$reload_output" | wc -l) -le 1 ]] ||
  fail 'zoxide prompt hook was duplicated on reload'
[[ $reload_output != *'history -r'* ]] ||
  fail 'legacy full history reload remains in PROMPT_COMMAND'
assert_contains "$reload_output" 'settings=100000:100000:3:on:on:on'
assert_contains "$reload_output" 'venv_disable_prompt=1'

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

link_command vi
link_command vim
editor_log=$test_root/editors.log
independent_output=$(
  TEST_COMMAND_MODE=independent TEST_EDITOR_LOG="$editor_log" \
    run_scenario independent-editors \
    env HOME="$reload_home" PATH="$test_root/bin:$original_path" TERM=xterm-256color \
    bash --noprofile --norc -i
)
assert_contains "$independent_output" 'vi=file vim=file'
assert_contains "$(<"$editor_log")" 'vi:first'
assert_contains "$(<"$editor_log")" 'vim:second'

checkout_with_spaces="$test_root/checkout with spaces"
mkdir -p "$checkout_with_spaces/scripts"
custom_output=$(
  run_scenario custom-dotfiles \
    env HOME="$reload_home" DOTFILES="$checkout_with_spaces" \
    PATH="$test_root/bin:$original_path" TERM=xterm-256color \
    bash --noprofile --norc -i
)
assert_contains "$custom_output" "dotfiles=$checkout_with_spaces pwd=$checkout_with_spaces"

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
assert_contains "$path_output" "terraform=$path_home/.asdf/shims/terraform"
path_line=$(grep '^path=' <<<"$path_output")
[[ ${path_line#path=} == "$path_home/.venv/bin:"* ]] ||
  fail 'active virtual environment lost PATH precedence'

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

stale_vz_output=$(
  run_scenario stale-vz \
    env HOME="$reload_home" PATH="$test_root/bin:$original_path"
)
[[ $stale_vz_output == 'editors=v,vold vz=removed' ]] ||
  fail 'alias reload did not remove stale vz while preserving v and vold'

printf 'Bash tests passed\n'
