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
  exec {lock_fd}<"$test_home/dotfiles-releases"
  flock -x "$lock_fd"
  : >"$lock_ready"
  exec sleep 30
) &
lock_holder_pid=$!
for ((attempt = 0; attempt < 200; attempt++)); do
  [[ ! -e $lock_ready ]] || break
  sleep 0.02
done
[[ -e $lock_ready ]] || fail 'lock holder did not become ready'
for command in install set uninstall health; do
  argument=$id_one
  [[ $command != install ]] || argument=$artifact_one
  if run_manager "$command" "$argument" >"$test_root/locked-$command.log" 2>&1; then
    fail "concurrent $command was accepted"
  fi
  [[ $(<"$test_root/locked-$command.log") == *'another release operation is running'* ]] ||
    fail "$command did not report the concurrency conflict"
done
run_manager verify "$artifact_one" >/dev/null
run_manager list >"$test_root/locked-list.log"
[[ $(<"$test_root/locked-list.log") == *"$id_one"* && ! -e $test_home/dotfiles-releases/.state ]] ||
  fail 'read commands required mutation state'
kill -KILL "$lock_holder_pid"
wait "$lock_holder_pid" 2>/dev/null || true
lock_holder_pid=
run_manager install "$artifact_one" >/dev/null
run_manager uninstall >/dev/null

printf 'dotfiles_release: locking passed\n'
