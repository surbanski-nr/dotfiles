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

test_repo="$test_root/repository"
test_home="$test_root/home"
mkdir -p "$test_repo/scripts" "$test_home/bin"
cp "$repo_dir/setup-asdf" "$test_repo/setup-asdf"
cp "$repo_dir/scripts/setup-lib" "$test_repo/scripts/setup-lib"
cp "$repo_dir/versions.env" "$test_repo/versions.env"

cat >"$test_home/bin/kubectl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod 0755 "$test_home/bin/kubectl"
set +e
conflict_output=$(HOME="$test_home" "$test_repo/setup-asdf" kubectl 2>&1)
conflict_status=$?
set -e
[[ $conflict_status -ne 0 ]] || fail 'direct kubectl launcher conflict was accepted'
[[ $conflict_output == *'conflicts with the direct launcher'* ]] ||
  fail 'direct launcher conflict was not reported'
[[ ! -e $test_home/bin/asdf && ! -e $test_home/.asdf ]] ||
  fail 'provider conflict changed the asdf installation'

rm "$test_home/bin/kubectl"
mkdir -p "$test_home/.local/state/dotfiles/setup-asdf/lock"
set +e
lock_output=$(HOME="$test_home" "$test_repo/setup-asdf" kubectl 2>&1)
lock_status=$?
set -e
[[ $lock_status -ne 0 ]] || fail 'concurrent setup-asdf lock was ignored'
[[ $lock_output == *'another setup-asdf process is running'* ]] ||
  fail 'concurrent setup-asdf did not report the lock'
[[ ! -e $test_home/bin/asdf ]] || fail 'lock conflict installed asdf'

printf 'Setup asdf tests passed\n'
