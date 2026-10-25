#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture
cp "$repo_dir/setup-asdf" "$test_repository/setup-asdf"

run_setup "$test_home" "$test_repository" "$archive_root" k9s >/dev/null

assert_locked() {
  local installer=$1 name=$2 output

  if output=$(HOME="$test_home" "$test_repository/$installer" "$name" 2>&1); then
    fail "$installer ignored the shared online installation lock"
  fi
  [[ $output == *'another online installer is running'* ]] ||
    fail "$installer did not report the shared lock"
}

lock_path=$test_home/.local/state/dotfiles/setup.lock
exec {test_lock_fd}>"$lock_path"
flock -n "$test_lock_fd"
assert_locked setup-tools k9s
assert_locked setup-tools yq
assert_locked setup-asdf terraform
exec {test_lock_fd}>&-
run_setup "$test_home" "$test_repository" "$archive_root" k9s >/dev/null

# The lock is shared even when XDG state lives outside the target home.
test_xdg=$test_root/'shared state elsewhere'
mkdir -p "$test_xdg/dotfiles"
exec {test_lock_fd}>"$test_xdg/dotfiles/setup.lock"
flock -n "$test_lock_fd"
XDG_STATE_HOME="$test_xdg" assert_locked setup-tools k9s
XDG_STATE_HOME="$test_xdg" assert_locked setup-asdf terraform
exec {test_lock_fd}>&-

mkdir -p "$test_root/blocking-download"
cat >"$test_root/blocking-download/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$$" >"$TEST_LOCK_READY"
exec sleep 30
EOF
chmod 0755 "$test_root/blocking-download/curl"

# Exercise both directions with an actual installer holding the lock. Its
# download child inherits the descriptor and must keep the lock after SIGKILL.
for installer in setup-tools setup-asdf; do
  if [[ $installer == setup-tools ]]; then name=yq; other=setup-asdf; other_name=terraform
  else name=terraform; other=setup-tools; other_name=k9s
  fi
  ready=$test_root/ready-$installer
  HOME="$test_home" TEST_LOCK_READY="$ready" \
    PATH="$test_root/blocking-download:$PATH" \
    "$test_repository/$installer" "$name" >"$test_root/holder-$installer.log" 2>&1 &
  killed_lock_pid=$!
  for ((attempt = 0; attempt < 100; attempt++)); do
    [[ ! -e $ready ]] || break
    sleep 0.02
  done
  [[ -f $ready ]] || fail "$installer did not reach the blocked download"
  killed_lock_child_pid=$(<"$ready")
  assert_locked "$other" "$other_name"
  kill -KILL "$killed_lock_pid"
  wait "$killed_lock_pid" 2>/dev/null || true
  killed_lock_pid=
  assert_locked "$other" "$other_name"
  kill -KILL "$killed_lock_child_pid"
  killed_lock_child_pid=
  for ((attempt = 0; attempt < 100; attempt++)); do
    if flock -n "$lock_path" true; then break; fi
    sleep 0.02
  done
  run_setup "$test_home" "$test_repository" "$archive_root" k9s >/dev/null
done

invalid_lock_home=$test_root/invalid-lock-home
mkdir -p "$invalid_lock_home/.local/state/dotfiles/setup.lock"
if run_setup "$invalid_lock_home" "$test_repository" "$archive_root" k9s \
  >"$test_root/invalid-lock.log" 2>&1; then
  fail 'an invalid directory lock was silently removed'
fi
[[ -d $invalid_lock_home/.local/state/dotfiles/setup.lock ]] ||
  fail 'invalid lock path was changed'

printf 'setup_tools: locking passed\n'
