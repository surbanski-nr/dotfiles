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

printf 'Setup system tests passed\n'
