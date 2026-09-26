#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../scripts/nvim2-release
source "$repo_dir/scripts/nvim2-release"

test_root=$(mktemp -d)
cleanup() {
  local status=$?
  find "$test_root" -depth -delete
  exit "$status"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

expect_failure() {
  local expected=$1
  shift
  local output
  local status

  set +e
  output=$("$@" 2>&1)
  status=$?
  set -e
  [[ $status -ne 0 ]] || fail "command unexpectedly passed: $*"
  [[ $output == *"$expected"* ]] ||
    fail "failure did not contain '$expected': $output"
}

missing_uid=4294967294
[[ -z $(lookup_uid_owner "$missing_uid") ]]

current_uid=$(id -u)
[[ $(lookup_uid_owner "$current_uid") == "$(id -un)" ]]

DEBIAN_TARGET_USER=debian-user
DEBIAN_TARGET_UID=1234
DEBIAN_TARGET_HOME=/home/debian-user
UBUNTU_TARGET_USER=ubuntu-user
UBUNTU_TARGET_UID=1235
UBUNTU_TARGET_HOME=/home/ubuntu-user
AMZN_TARGET_USER=amazon-user
AMZN_TARGET_UID=1236
AMZN_TARGET_HOME=/home/amazon-user

configure_target debian-13-x86_64
[[ $TARGET_USER == debian-user && $TARGET_UID == 1234 &&
  $TARGET_HOME == /home/debian-user ]]
configure_target ubuntu-24.04-x86_64
[[ $TARGET_USER == ubuntu-user && $TARGET_UID == 1235 &&
  $TARGET_HOME == /home/ubuntu-user ]]
configure_target amzn-2023-x86_64
[[ $TARGET_USER == amazon-user && $TARGET_UID == 1236 &&
  $TARGET_HOME == /home/amazon-user ]]

DEBIAN_TARGET_HOME=/srv/debian-user
expect_failure 'does not match user' configure_target debian-13-x86_64
DEBIAN_TARGET_HOME=/home/debian-user

cat >"$test_root/os-release" <<'EOF'
ID=debian
VERSION_ID=13
EOF
NVIM2_OS_RELEASE_FILE=$test_root/os-release
validate_platform debian-13-x86_64
expect_failure 'requires OS ID ubuntu' validate_platform ubuntu-24.04-x86_64
sed -i 's/VERSION_ID=13/VERSION_ID=12/' "$test_root/os-release"
expect_failure 'requires OS version 13' validate_platform debian-13-x86_64

identity_repo=$test_root/repository
mkdir -p "$identity_repo"
git -C "$identity_repo" init -q
git -C "$identity_repo" config user.name test
git -C "$identity_repo" config user.email test@example.invalid
printf 'release input\n' >"$identity_repo/input"
git -C "$identity_repo" add input
git -C "$identity_repo" commit -qm initial
SOURCE_COMMIT=$(git -C "$identity_repo" rev-parse HEAD)
RELEASE_TAG=nvim2-${SOURCE_COMMIT:0:12}
validate_release_identity "$identity_repo"
RELEASE_TAG=nvim2-deadbee
expect_failure 'does not match SOURCE_COMMIT' validate_release_identity "$identity_repo"
RELEASE_TAG=nvim2-${SOURCE_COMMIT:0:12}
printf 'dirty\n' >>"$identity_repo/input"
expect_failure 'must be clean' validate_release_identity "$identity_repo"

TARGET_HOME=$test_root/python-home
mkdir -p "$TARGET_HOME/bin"
ln -s "$(command -v python3)" "$TARGET_HOME/bin/python3"
python_path=$(readlink -f -- "$TARGET_HOME/bin/python3")
python_version=$(python3 -c \
  'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
validate_runtime_python "$python_path" "$python_version"
expect_failure 'artifact requires /missing/python' \
  validate_runtime_python /missing/python "$python_version"
expect_failure 'artifact requires 0.0' \
  validate_runtime_python "$python_path" 0.0

artifact=$test_root/artifact
mkdir -p "$artifact"
printf 'release\n' >"$artifact/release.env"
printf '%064d  release.env\n' 0 >"$artifact/SHA256SUMS"
expect_failure 'FAILED' bash -c \
  "source '$repo_dir/scripts/nvim2-release'; require_root() { :; }; verify_release debian-13-x86_64 '$artifact'"

printf 'Nvim2 release tests passed\n'
