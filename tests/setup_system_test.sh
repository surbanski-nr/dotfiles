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
debian_release=$test_root/debian-os-release
amazon_release=$test_root/amazon-os-release
mkdir -p "$fixture_bin"
printf 'ID=debian\nVERSION_ID=13\n' >"$debian_release"
printf 'ID=amzn\nVERSION_ID=2023\n' >"$amazon_release"
cat >"$fixture_bin/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == -- ]] && shift
exec "$@"
EOF
cat >"$fixture_bin/apt-get" <<'EOF'
#!/usr/bin/env bash
[[ ${TEST_PACKAGE_FAIL:-} != "apt-get:${1:-}" ]] || exit 71
printf 'apt-get' >>"$TEST_PACKAGE_LOG"
printf '\t%s' "$@" >>"$TEST_PACKAGE_LOG"
printf '\n' >>"$TEST_PACKAGE_LOG"
EOF
cat >"$fixture_bin/dnf" <<'EOF'
#!/usr/bin/env bash
[[ ${TEST_PACKAGE_FAIL:-} != "dnf:${1:-}" ]] || exit 72
printf 'dnf' >>"$TEST_PACKAGE_LOG"
printf '\t%s' "$@" >>"$TEST_PACKAGE_LOG"
printf '\n' >>"$TEST_PACKAGE_LOG"
EOF
cat >"$fixture_bin/rpm" <<'EOF'
#!/usr/bin/env bash
[[ ${TEST_RPM_MINIMAL:-0} == 1 ]]
EOF
chmod 0755 "$fixture_bin/sudo" "$fixture_bin/apt-get" "$fixture_bin/dnf" \
  "$fixture_bin/rpm"

if PATH="$fixture_bin:$PATH" TEST_PACKAGE_LOG="$package_log" \
  "$repo_dir/setup-system" --runtime >"$test_root/retired-flag.log" 2>&1; then
  fail 'setup-system accepted the retired --runtime flag'
fi
if PATH="$fixture_bin:$PATH" TEST_PACKAGE_LOG="$package_log" \
  "$repo_dir/setup-system" --offline-release extra >"$test_root/extra-argument.log" 2>&1; then
  fail 'setup-system accepted an argument after --offline-release'
fi
[[ ! -e $package_log ]] || fail 'invalid arguments reached the package manager'

for command_name in curl file gpg gpg-agent htop jq make mc python3 tmux vi vim; do
  ln -s /bin/true "$fixture_bin/$command_name"
done

for _ in 1 2; do
  PATH="$fixture_bin:$PATH" TEST_PACKAGE_LOG="$package_log" \
    SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" \
    "$repo_dir/setup-system" --offline-release >/dev/null
done
[[ $(grep -c $'^apt-get\tupdate$' "$package_log") -eq 2 ]] ||
  fail 'offline-release setup did not repeat the package index refresh'
[[ $(grep -c 'libevent-core-2.1-7t64' "$package_log") -eq 2 ]] ||
  fail 'offline-release setup omitted libevent runtime'
[[ $(grep -c 'diffutils' "$package_log") -eq 2 ]] ||
  fail 'offline-release setup omitted cmp runtime'
if grep $'^apt-get\tinstall' "$package_log" | grep -Eq $'\t(python3|tmux|build-essential)(\t|$)'; then
  fail 'offline-release setup included a connected-only package'
fi

: >"$package_log"
for _ in 1 2; do
  PATH="$fixture_bin:$PATH" TEST_PACKAGE_LOG="$package_log" \
    SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" \
    "$repo_dir/setup-system" >/dev/null
done
[[ $(grep -c $'^apt-get\tupdate$' "$package_log") -eq 2 ]] ||
  fail 'connected setup did not repeat the package index refresh'
grep $'^apt-get\tinstall' "$package_log" | grep -F $'\tbuild-essential\t' >/dev/null ||
  fail 'connected setup omitted build prerequisites'
grep $'^apt-get\tinstall' "$package_log" | grep -F $'\tpython3\t' >/dev/null ||
  fail 'connected setup omitted its Python provider'

: >"$package_log"
for _ in 1 2; do
  PATH="$fixture_bin:$PATH" TEST_PACKAGE_LOG="$package_log" TEST_RPM_MINIMAL=1 \
    SETUP_SYSTEM_OS_RELEASE_FILE="$amazon_release" \
    "$repo_dir/setup-system" >/dev/null
done
[[ $(grep -c $'^dnf\tswap\t-y\tgnupg2-minimal\tgnupg2$' "$package_log") -eq 2 ]] ||
  fail 'Amazon connected setup did not preserve the GnuPG swap'
if grep $'^dnf\tinstall' "$package_log" | grep -Eq $'\t(cargo|clang-devel)(\t|$)'; then
  fail 'Amazon connected setup inherited builder-only packages'
fi
grep $'^dnf\tinstall' "$package_log" | grep -F $'\t--allowerasing\t' >/dev/null ||
  fail 'Amazon setup omitted --allowerasing'

: >"$package_log"
PATH="$fixture_bin:$PATH" TEST_PACKAGE_LOG="$package_log" TEST_RPM_MINIMAL=0 \
  SETUP_SYSTEM_OS_RELEASE_FILE="$amazon_release" \
  "$repo_dir/setup-system" >/dev/null
grep -Fx $'dnf\tinstall\t-y\tgnupg2' "$package_log" >/dev/null ||
  fail 'Amazon connected setup did not install full GnuPG when minimal was absent'

# shellcheck source=../scripts/setup-lib
source "$repo_dir/scripts/setup-lib"
PROGRAM=setup-system-test
system_package_list amzn:2023 build
printf '%s\n' "${SETUP_SYSTEM_PACKAGES[@]}" | grep -Fx cargo >/dev/null ||
  fail 'Amazon build omitted cargo'
printf '%s\n' "${SETUP_SYSTEM_PACKAGES[@]}" | grep -Fx clang-devel >/dev/null ||
  fail 'Amazon build omitted clang-devel'
system_package_list amzn:2023 connected
if printf '%s\n' "${SETUP_SYSTEM_PACKAGES[@]}" | grep -Eq '^(cargo|clang-devel)$'; then
  fail 'Amazon connected role contains a builder-only package'
fi
[[ $(printf '%s\n' "${SETUP_SYSTEM_PACKAGES[@]}" | sort -u | wc -l) -eq ${#SETUP_SYSTEM_PACKAGES[@]} ]] ||
  fail 'Amazon connected package list contains duplicates'

set +e
PATH="$fixture_bin:$PATH" TEST_PACKAGE_LOG="$package_log" \
  TEST_PACKAGE_FAIL=apt-get:update SETUP_SYSTEM_OS_RELEASE_FILE="$debian_release" \
  "$repo_dir/setup-system" --offline-release >/dev/null 2>&1
apt_failure=$?
PATH="$fixture_bin:$PATH" TEST_PACKAGE_LOG="$package_log" TEST_RPM_MINIMAL=0 \
  TEST_PACKAGE_FAIL=dnf:install SETUP_SYSTEM_OS_RELEASE_FILE="$amazon_release" \
  "$repo_dir/setup-system" --offline-release >/dev/null 2>&1
dnf_failure=$?
set -e
[[ $apt_failure -eq 71 ]] || fail 'apt failure was hidden'
[[ $dnf_failure -eq 72 ]] || fail 'dnf failure was hidden'

printf 'Setup system tests passed\n'
