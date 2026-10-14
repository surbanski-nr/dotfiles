#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

run_setup "$test_home" "$test_repository" "$archive_root" k9s >/dev/null

exec {test_lock_fd}>"$test_home/.local/state/dotfiles/setup-tools/locks/k9s.lock"
flock -n "$test_lock_fd"
set +e
lock_output=$(run_setup "$test_home" "$test_repository" "$archive_root" k9s 2>&1)
lock_status=$?
set -e
[[ $lock_status -ne 0 ]] || fail 'concurrent setup lock was ignored'
[[ $lock_output == *'another setup-tools process owns k9s'* ]] ||
  fail 'concurrent setup did not report its lock owner'
exec {test_lock_fd}>&-
run_setup "$test_home" "$test_repository" "$archive_root" k9s >/dev/null

# SIGKILL cannot run cleanup traps, but must still release a process-held lock.
bash -c 'exec {fd}>"$1"; flock -n "$fd"; : >"$2"; exec sleep 30' \
  bash "$test_home/.local/state/dotfiles/setup-tools/locks/k9s.lock" \
  "$test_root/killed-lock-ready" &
killed_lock_pid=$!
for ((attempt = 0; attempt < 100; attempt++)); do
  [[ ! -e $test_root/killed-lock-ready ]] || break
  sleep 0.02
done
[[ -e $test_root/killed-lock-ready ]] || fail 'lock holder did not become ready'
kill -KILL "$killed_lock_pid"
wait "$killed_lock_pid" 2>/dev/null || true
killed_lock_pid=
run_setup "$test_home" "$test_repository" "$archive_root" k9s >/dev/null

legacy_lock_home=$test_root/legacy-lock-home
mkdir -p "$legacy_lock_home/.local/state/dotfiles/setup-tools/locks/k9s.lock"
if run_setup "$legacy_lock_home" "$test_repository" "$archive_root" k9s \
  >"$test_root/legacy-lock.log" 2>&1; then
  fail 'legacy directory lock was silently removed'
fi
[[ -d $legacy_lock_home/.local/state/dotfiles/setup-tools/locks/k9s.lock ]] ||
  fail 'legacy directory lock was changed'

printf 'setup_tools: locking passed\n'
