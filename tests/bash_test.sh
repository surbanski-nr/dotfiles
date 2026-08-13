#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2123,SC2329

set -euo pipefail

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
bashrc=$repo_dir/bash/.bashrc
profile=$repo_dir/bash/.bash_profile
aliases=$repo_dir/bash/.bash_aliases
test_root=$(mktemp -d)

cleanup() {
  local status=$?
  PATH=${original_path:-/usr/bin:/bin}
  rm -rf -- "$test_root"
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

make_stub() {
  local name=$1
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$test_root/bin/$name"
  chmod +x "$test_root/bin/$name"
}

for file in "$bashrc" "$profile" "$aliases"; do
  bash -n "$file"
done

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck --shell=bash --external-sources -e SC1090,SC1091 \
    "$bashrc" "$profile" "$aliases"
fi

mkdir -p "$test_root/bin"
for command_name in git tmux fzf less mc; do
  make_stub "$command_name"
done

source "$aliases"

original_path=$PATH
PATH=$test_root/bin
set +e
check_output=$(dotfiles-check 2>&1)
check_status=$?
set -e
[[ $check_status -eq 1 ]] || fail 'dotfiles-check accepted a missing required command'
assert_contains "$check_output" 'MISSING nvim'
assert_contains "$check_output" 'MISSING zoxide'

PATH=$original_path
make_stub nvim
PATH=$test_root/bin
dotfiles-check >/dev/null || fail 'optional tools changed dotfiles-check exit status'
printf '%s\n' \
  '#!/bin/bash' \
  'printf "app=%s argc=%s first=%s\n" "$NVIM_APPNAME" "$#" "$1"' \
  >"$test_root/bin/nvim"
/usr/bin/chmod +x "$test_root/bin/nvim"
editor_output=$(v 'file with space')
[[ $editor_output == 'app=nvim2 argc=1 first=file with space' ]] ||
  fail 'v did not preserve the Nvim2 profile or argument quoting'

PATH=$original_path
mkdir -p "$test_root/empty"
PATH=$test_root/empty
set +e
missing_output=$(kl pod-name 2>&1)
missing_status=$?
set -e
[[ $missing_status -eq 127 ]] || fail 'missing kubectl did not return 127'
[[ $missing_output == 'dotfiles: kl requires kubectl' ]] || fail 'missing dependency message was noisy or unclear'
PATH=$original_path

kubectl() {
  printf '%s\n' pod-a=-v pod-b
}
filtered=$(kgp -v)
assert_contains "$filtered" 'pod-a=-v'

kubectl() {
  printf 'simulated kubectl failure\n' >&2
  return 42
}
set +e
kpl api >/dev/null 2>&1
kpl_status=$?
set -e
[[ $kpl_status -eq 42 ]] || fail 'kpl hid kubectl get pods failure'

bat() {
  while IFS= read -r _; do :; done
}
set +e
kl api >/dev/null 2>&1
kl_status=$?
set -e
[[ $kl_status -eq 42 ]] || fail 'kl hid the left side of its pipeline'
unset -f bat kubectl

mkdir -p "$test_root/logs"
(
  cd "$test_root/logs"
  kubectl() {
    if [[ $1 == get ]]; then
      printf '%s\n' api-1 worker-1
    else
      printf 'logs for %s\n' "$2"
    fi
  }
  kpl api
  [[ $(<api-1.log) == 'logs for api-1' ]]
  [[ ! -e worker-1.log ]]
) || fail 'kpl did not write only successful matching pod logs'

reload_home=$test_root/reload-home
mkdir -p "$reload_home"
ln -s "$aliases" "$reload_home/.bash_aliases"
reload_output=$(
  timeout 15 env HOME="$reload_home" BASHRC="$bashrc" TERM=xterm-256color \
    bash --noprofile --norc -ic '
      unset PROMPT_COMMAND
      source "$BASHRC"
      source "$BASHRC"
      source "$BASHRC"
      declare -p PROMPT_COMMAND
      printf "settings=%s:%s:%s:%s:%s:%s\n" \
        "$HISTSIZE" "$HISTFILESIZE" "$IGNOREEOF" \
        "$(set -o | awk '\''$1 == "pipefail" { print $2 }'\'')" \
        "$(shopt -q histverify && echo on || echo off)" \
        "$(shopt -q checkjobs && echo on || echo off)"
    ' 2>&1
)
[[ $(grep -o '_dotfiles_history_sync' <<<"$reload_output" | wc -l) -eq 1 ]] ||
  fail 'history prompt hook was duplicated on reload'
[[ $(grep -o '__zoxide_hook' <<<"$reload_output" | wc -l) -le 1 ]] ||
  fail 'zoxide prompt hook was duplicated on reload'
[[ $reload_output != *'history -r'* ]] || fail 'legacy full history reload remains in PROMPT_COMMAND'
assert_contains "$reload_output" 'settings=100000:100000:3:on:on:on'

broken_output=$(
  timeout 15 env HOME="$reload_home" BASHRC="$bashrc" TERM=xterm-256color \
    bash --noprofile --norc -ic '
      zoxide() { return 9; }
      source "$BASHRC"
    ' 2>&1
)
assert_contains "$broken_output" 'dotfiles: zoxide initialization failed'
[[ $broken_output != *'command not found'* ]] || fail 'broken integration emitted raw shell errors'

invalid_output=$(
  timeout 15 env HOME="$reload_home" BASHRC="$bashrc" TERM=xterm-256color \
    bash --noprofile --norc -ic '
      zoxide() { printf "if broken"; }
      source "$BASHRC"
      printf "continued=yes\n"
    ' 2>&1
)
assert_contains "$invalid_output" 'dotfiles: zoxide returned invalid shell initialization'
assert_contains "$invalid_output" 'continued=yes'
[[ $invalid_output != *'syntax error'* ]] || fail 'invalid integration emitted raw shell errors'

agent_home=$test_root/agent-home
agent_bin=$test_root/agent-bin
agent_log=$test_root/agent.log
mkdir -p "$agent_home/.ssh" "$agent_bin"
printf 'invalid key\n' >"$agent_home/.ssh/github"
chmod 600 "$agent_home/.ssh/github"
printf ':\n' >"$agent_home/.bashrc"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "ssh-agent %s\n" "$*" >>"$TEST_AGENT_LOG"' \
  'if [[ $1 == -s ]]; then' \
  '  printf "SSH_AUTH_SOCK=%q; export SSH_AUTH_SOCK;\n" "$HOME/fake-agent.sock"' \
  '  printf "SSH_AGENT_PID=4242; export SSH_AGENT_PID;\n"' \
  'fi' >"$agent_bin/ssh-agent"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "ssh-add %s\n" "$*" >>"$TEST_AGENT_LOG"' \
  'printf "invalid key material\n" >&2' \
  'exit 42' >"$agent_bin/ssh-add"
chmod +x "$agent_bin/ssh-agent" "$agent_bin/ssh-add"

profile_output=$(
  env -i HOME="$agent_home" PATH="$agent_bin:/usr/bin:/bin" \
    TEST_AGENT_LOG="$agent_log" PROFILE="$profile" bash --noprofile --norc -c '
      source "$PROFILE"
      printf "profile_status=%s sock=%s pid=%s\n" \
        "$?" "${SSH_AUTH_SOCK:-unset}" "${SSH_AGENT_PID:-unset}"
    ' 2>&1
)
assert_contains "$profile_output" 'dotfiles: failed to add ~/.ssh/github: invalid key material'
assert_contains "$profile_output" 'profile_status=0 sock=unset pid=unset'
assert_contains "$(<"$agent_log")" 'ssh-agent -k'

stale_output=$(
  env -i HOME="$agent_home" PATH=/usr/bin:/bin SSH_AUTH_SOCK=/missing/agent.sock \
    PROFILE="$profile" bash --noprofile --norc -c '
      rm -f "$HOME/.ssh/github"
      source "$PROFILE"
      printf "stale_status=%s sock=%s\n" "$?" "${SSH_AUTH_SOCK:-unset}"
    ' 2>&1
)
assert_contains "$stale_output" 'dotfiles: SSH_AUTH_SOCK is not a socket: /missing/agent.sock'
assert_contains "$stale_output" 'stale_status=0 sock=unset'

printf 'Bash tests passed\n'
