#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)

cleanup() {
  find "$test_root" -depth -delete
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p "$test_root/no-sudo" "$test_root/wrong-arch"
ln -s "$(command -v dirname)" "$test_root/no-sudo/dirname"
ln -s "$(command -v uname)" "$test_root/no-sudo/uname"
set +e
missing_sudo_output=$(PATH="$test_root/no-sudo" /bin/bash "$repo_dir/setup-system" 2>&1)
missing_sudo_status=$?
set -e
[[ $missing_sudo_status -ne 0 ]] || fail 'setup-system accepted a missing sudo command'
[[ $missing_sudo_output == *'required command is missing: sudo'* ]] ||
  fail 'setup-system did not report missing sudo'

ln -s "$(command -v dirname)" "$test_root/wrong-arch/dirname"
cat >"$test_root/wrong-arch/uname" <<'EOF'
#!/bin/sh
case $1 in
  -s) printf 'Linux\n' ;;
  -m) printf 'aarch64\n' ;;
  *) exit 1 ;;
esac
EOF
chmod 0755 "$test_root/wrong-arch/uname"
set +e
wrong_arch_output=$(PATH="$test_root/wrong-arch" /bin/bash "$repo_dir/setup-system" 2>&1)
wrong_arch_status=$?
set -e
[[ $wrong_arch_status -ne 0 ]] || fail 'setup-system accepted an unsupported architecture'
[[ $wrong_arch_output == *'only Linux x86-64 is supported'* ]] ||
  fail 'setup-system did not report the unsupported architecture'

fixture_bin=$test_root/fixture-bin
package_log=$test_root/packages.log
mkdir -p "$fixture_bin"
cat >"$fixture_bin/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == -- ]] && shift
exec "$@"
EOF
cat >"$fixture_bin/apt-get" <<'EOF'
#!/usr/bin/env bash
printf 'apt-get' >>"$TEST_PACKAGE_LOG"
printf '\t%s' "$@" >>"$TEST_PACKAGE_LOG"
printf '\n' >>"$TEST_PACKAGE_LOG"
EOF
chmod 0755 "$fixture_bin/sudo" "$fixture_bin/apt-get"

for _ in 1 2; do
  PATH="$fixture_bin:$PATH" TEST_PACKAGE_LOG="$package_log" \
    "$repo_dir/setup-system" --runtime >/dev/null
done
[[ $(grep -c $'^apt-get\tupdate$' "$package_log") -eq 2 ]] ||
  fail 'runtime setup did not repeat the package index refresh'
[[ $(grep -c 'libevent-core-2.1-7t64' "$package_log") -eq 2 ]] ||
  fail 'runtime setup omitted libevent runtime'
[[ $(grep -c 'diffutils' "$package_log") -eq 2 ]] ||
  fail 'runtime setup omitted cmp runtime'
if grep $'^apt-get\tinstall' "$package_log" | grep -Eq $'\t(python3|tmux|build-essential)(\t|$)'; then
  fail 'runtime setup included a connected-only package'
fi

: >"$package_log"
for _ in 1 2; do
  PATH="$fixture_bin:$PATH" TEST_PACKAGE_LOG="$package_log" \
    "$repo_dir/setup-system" >/dev/null
done
[[ $(grep -c $'^apt-get\tupdate$' "$package_log") -eq 2 ]] ||
  fail 'connected setup did not repeat the package index refresh'
grep $'^apt-get\tinstall' "$package_log" | grep -F $'\tbuild-essential\t' >/dev/null ||
  fail 'connected setup omitted build prerequisites'
grep $'^apt-get\tinstall' "$package_log" | grep -F $'\tpython3\t' >/dev/null ||
  fail 'connected setup omitted its Python provider'

printf 'Setup system tests passed\n'
