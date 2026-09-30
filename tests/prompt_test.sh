#!/usr/bin/env bash

if [[ ${PROMPT_TEST_MODE:-} == interactive ]]; then
  set -eo pipefail

  : "${PROMPT_TEST_OMP:?}"
  : "${PROMPT_TEST_PYTHON:?}"
  : "${PROMPT_TEST_REPO:?}"
  : "${PROMPT_TEST_ROOT:?}"
  config=$PROMPT_TEST_REPO/oh-my-posh/.oh-my-posh.omp.json

  fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
  }

  assert_contains() {
    local value=$1
    local expected=$2
    [[ $value == *"$expected"* ]] || fail "expected prompt to contain: $expected"
  }

  assert_not_contains() {
    local value=$1
    local unexpected=$2
    [[ $value != *"$unexpected"* ]] || fail "prompt unexpectedly contained: $unexpected"
  }

  render_prompt() {
    "$PROMPT_TEST_OMP" print primary --plain --config "$config" \
      --pwd "$PROMPT_TEST_ROOT/project"
  }

  # shellcheck source=../bash/.bashrc
  source "$PROMPT_TEST_REPO/bash/.bashrc"
  [[ $VIRTUAL_ENV_DISABLE_PROMPT == 1 ]] ||
    fail 'Bash startup did not disable activation-script prompt changes'
  [[ $(declare -p PROMPT_COMMAND) == *'[0]="_dotfiles_sync_virtual_env_prompt"'* ]] ||
    fail 'venv state hook does not run before prompt rendering'

  unset VIRTUAL_ENV VIRTUAL_ENV_PROMPT
  _dotfiles_sync_virtual_env_prompt
  dormant_prompt=$(render_prompt)
  assert_not_contains "$dormant_prompt" '(.venv)'

  PS1='unchanged> '
  # shellcheck disable=SC1091
  source "$PROMPT_TEST_ROOT/python env/bin/activate"
  [[ $PS1 == 'unchanged> ' ]] || fail 'python venv activation changed PS1'
  _dotfiles_sync_virtual_env_prompt
  python_prompt=$(render_prompt)
  assert_contains "$python_prompt" '(python env) '

  VIRTUAL_ENV_PROMPT='(short label) '
  export VIRTUAL_ENV_PROMPT
  custom_prompt=$(render_prompt)
  assert_contains "$custom_prompt" '(short label) '
  assert_not_contains "$custom_prompt" '(python env) '

  deactivate
  _dotfiles_sync_virtual_env_prompt
  [[ -z ${VIRTUAL_ENV:-} ]] || fail 'python venv did not deactivate'
  deactivated_prompt=$(render_prompt)
  assert_not_contains "$deactivated_prompt" '(python env)'
  assert_not_contains "$deactivated_prompt" '(short label)'

  PS1='unchanged> '
  # shellcheck disable=SC1091
  source "$PROMPT_TEST_ROOT/uv env/bin/activate"
  [[ $PS1 == 'unchanged> ' ]] || fail 'uv venv activation changed PS1'
  _dotfiles_sync_virtual_env_prompt
  uv_prompt=$(render_prompt)
  assert_contains "$uv_prompt" '(uv env) '

  # Python 3.9 does not clear an older activation script's prompt label.
  # The pre-render hook must reject that stale value when the venv changes.
  # shellcheck disable=SC1091
  source "$PROMPT_TEST_ROOT/python env/bin/activate"
  _dotfiles_sync_virtual_env_prompt
  switched_prompt=$(render_prompt)
  assert_contains "$switched_prompt" '(python env) '
  assert_not_contains "$switched_prompt" '(uv env) '
  deactivate
  _dotfiles_sync_virtual_env_prompt

  unset VIRTUAL_ENV VIRTUAL_ENV_PROMPT
  uv run --no-project --python "$PROMPT_TEST_PYTHON" \
    python -c 'print("uv run completed")' | command grep -qx 'uv run completed'
  [[ -z ${VIRTUAL_ENV:-} ]] || fail 'uv run changed the parent VIRTUAL_ENV'
  assert_not_contains "$(render_prompt)" '(uv env)'

  invocation_log=$PROMPT_TEST_ROOT/prompt-discovery.log
  for command_name in python python3 uv; do
    cat >"$PROMPT_TEST_ROOT/poison-bin/$command_name" <<EOF
#!/bin/sh
printf '%s\\n' '$command_name' >>'$invocation_log'
exit 99
EOF
    chmod +x "$PROMPT_TEST_ROOT/poison-bin/$command_name"
  done
  PATH="$PROMPT_TEST_ROOT/poison-bin:$PATH"
  export PATH VIRTUAL_ENV="$PROMPT_TEST_ROOT/environment with spaces"
  unset VIRTUAL_ENV_PROMPT
  _dotfiles_sync_virtual_env_prompt
  fallback_prompt=$(render_prompt)
  assert_contains "$fallback_prompt" '(environment with spaces) '
  [[ ! -e $invocation_log ]] || fail 'prompt rendering launched python or uv'

  printf 'Prompt tests passed\n'
  exit 0
fi

set -euo pipefail

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)

cleanup() {
  local status=$?
  trap - EXIT
  find "$test_root" -depth -delete
  exit "$status"
}
trap cleanup EXIT

mkdir -p "$test_root/home" "$test_root/project/.venv" "$test_root/poison-bin"
ln -s "$repo_dir/oh-my-posh/.oh-my-posh.omp.json" \
  "$test_root/home/.oh-my-posh.omp.json"
python_path=$(python3 -c 'import os, sys; print(os.path.realpath(sys.executable))')
"$python_path" -m venv "$test_root/python env"
uv venv --no-project --python "$python_path" "$test_root/uv env" >/dev/null

PROMPT_TEST_MODE=interactive \
PROMPT_TEST_OMP=$(command -v oh-my-posh) \
PROMPT_TEST_PYTHON=$python_path \
PROMPT_TEST_REPO=$repo_dir \
PROMPT_TEST_ROOT=$test_root \
HOME="$test_root/home" \
DOTFILES=$repo_dir \
TERM=xterm-256color \
bash --noprofile --norc -i "$repo_dir/tests/prompt_test.sh"
