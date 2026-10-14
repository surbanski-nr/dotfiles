#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

test_home=$test_root/locking-home
mkdir -p "$test_home"
run_manager install "$artifact_one" >/dev/null

lock_ready=$test_root/lock-ready
(
  exec {lock_fd}<"$test_home/dotfiles-releases/.state/lock"
  flock -x "$lock_fd"
  : >"$lock_ready"
  exec sleep 30
) &
lock_holder_pid=$!
for ((attempt = 0; attempt < 200; attempt++)); do
  [[ ! -e $lock_ready ]] || break
  sleep 0.05
done
[[ -e $lock_ready ]] || fail 'lock holder did not become ready'
set +e
lock_output=$(run_manager install "$artifact_one" 2>&1)
lock_status=$?
rollback_lock_output=$(run_manager rollback 2>&1)
rollback_lock_status=$?
list_lock_output=$(run_manager list 2>&1)
list_lock_status=$?
health_lock_output=$(run_manager health 2>&1)
health_lock_status=$?
set -e
[[ $lock_status -ne 0 && $lock_output == *'another release operation is running'* ]] ||
  fail 'concurrent install was accepted'
[[ $rollback_lock_status -ne 0 &&
  $rollback_lock_output == *'another release operation is running'* ]] ||
  fail 'second concurrent mutation was accepted'
[[ $list_lock_status -ne 0 &&
  $list_lock_output == *'another release operation is running'* ]] ||
  fail 'concurrent list was accepted'
[[ $health_lock_status -ne 0 &&
  $health_lock_output == *'another release operation is running'* ]] ||
  fail 'concurrent health was accepted'
kill -KILL "$lock_holder_pid"
wait "$lock_holder_pid" 2>/dev/null || true
lock_holder_pid=
run_manager install "$artifact_one" >/dev/null

printf 'dotfiles_release: locking passed\n'
