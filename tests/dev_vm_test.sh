#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
task_executable=${VALIDATION_TOOLS_DIR:-$repo_dir/bin}/task
test_root=$(mktemp -d)
shell_pid=
cleanup() {
  if [[ -n $shell_pid ]]; then
    touch "$test_root/release"
    wait "$shell_pid" || true
  fi
  find "$test_root" -depth -delete
}
trap cleanup EXIT
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

checkout=$test_root/'checkout with spaces'
mkdir -p "$checkout/.git" "$checkout/scripts" "$test_root/bin" "$test_root/state"
cp "$repo_dir/Taskfile.yml" "$checkout/Taskfile.yml"
cp "$repo_dir/release.env" "$checkout/release.env"
printf 'DEFAULT_DEV_PLATFORM=debian13\n' >>"$checkout/release.env"
cp "$checkout/release.env" "$test_root/dev-config.env"
cp "$repo_dir/scripts/dev-vm" "$repo_dir/scripts/dev-vm-setup" "$checkout/scripts/"
cp "$repo_dir/scripts/"*-lib "$checkout/scripts/"
# shellcheck source=../release.env
source "$checkout/release.env"
ln -s "$repo_dir/tests/fixtures/dev-vm/lxc" "$test_root/bin/lxc"
ln -s "$repo_dir/tests/fixtures/dev-vm/curl" "$test_root/bin/curl"
export TEST_DEV_STATE=$test_root/state TEST_DEV_LOG=$test_root/lxc.log TEST_DEV_PROJECT=fixture
export TEST_DEV_IMAGE_SHA256=${LXD_IMAGE_SHA256[amzn-2023-x86_64]}
export PATH="$test_root/bin:$PATH"

run_dev() {
  "$task_executable" --dir "$checkout" dev DEV_PROJECT=fixture "$@"
}
COLORTERM=truecolor run_dev >"$test_root/default.log" 2>&1
[[ $(<"$TEST_DEV_STATE/shell-colorterm") == truecolor ]] || fail 'guest shell lost host truecolor support'
vm=$(jq -r .name "$TEST_DEV_STATE"/vm-*.json)
[[ $vm == dotfiles-dev-debian13-*-* ]] || fail 'default task did not create a named Debian VM'
jq -e --arg root "$checkout" '
  .type == "virtual-machine" and .config["limits.cpu"] == "1" and
  .config["limits.memory"] == "16GiB" and .devices.root.size == "80GiB" and
  .devices.checkout.source == $root and .devices.checkout.path == "/workspace/dotfiles" and
  (.devices | keys == ["checkout", "root"])' "$TEST_DEV_STATE/vm-$vm.json" >/dev/null ||
  fail 'VM resources or checkout isolation are incorrect'
COLORTERM=24bit run_dev -- debian13 >"$test_root/reuse.log" 2>&1
[[ $(<"$TEST_DEV_STATE/shell-colorterm") == 24bit ]] || fail 'guest shell changed host color capability'
COLORTERM='' run_dev -- debian13 >"$test_root/no-colorterm.log" 2>&1
[[ ! -s $TEST_DEV_STATE/shell-colorterm ]] || fail 'guest shell forced unadvertised truecolor support'
grep -F "guest-shell $vm" "$test_root/reuse.log" >/dev/null || fail 'explicit Debian did not reuse the default VM'
[[ $(grep -c '^init ' "$TEST_DEV_LOG") == 1 ]] || fail 'reopening a shell created another VM'

TEST_DEV_SHELL_READY=$test_root/ready TEST_DEV_SHELL_RELEASE=$test_root/release \
  run_dev -- debian13 >"$test_root/held-shell.log" 2>&1 &
shell_pid=$!
deadline=$((SECONDS + 5))
until [[ -e $test_root/ready ]]; do
  ((SECONDS < deadline)) || fail 'first shell did not open'
  sleep 0.1
done
timeout 5s "$task_executable" --dir "$checkout" dev DEV_PROJECT=fixture -- debian13 \
  >"$test_root/concurrent-shell.log" 2>&1 || fail 'an interactive shell retained the preparation lock'
touch "$test_root/release"
wait "$shell_pid"
shell_pid=

TEST_DEV_PREPARE_CONNECTION_FAIL=1 run_dev -- debian13 >"$test_root/prepare-retry.log" 2>&1 ||
  fail 'an LXD connection failure stopped preparation instead of retrying it'
grep -F "guest-shell $vm" "$test_root/prepare-retry.log" >/dev/null ||
  fail 'retrying preparation did not open the guest shell'
if TEST_DEV_PREPARE_FAIL=42 run_dev -- debian13 >"$test_root/prepare-failure.log" 2>&1; then
  fail 'a preparation error opened the guest shell'
fi
if grep -q 'retrying preparation\|guest-shell' "$test_root/prepare-failure.log"; then
  fail 'a preparation error was retried or ignored'
fi
if TEST_DEV_PREPARE_FAIL=255 run_dev -- debian13 >"$test_root/connection-failure.log" 2>&1; then
  fail 'a persistent LXD connection failure opened the guest shell'
fi
[[ $(grep -c 'retrying preparation' "$test_root/connection-failure.log") == 2 ]] ||
  fail 'persistent LXD connection failures did not stop after three attempts'

for alias in ubuntu2404 ubuntu2604 amazonlinux2023; do
  run_dev DEV_CPUS=4 DEV_MEMORY=8GiB DEV_DISK=40GiB -- "$alias" >"$test_root/$alias.log" 2>&1
  jq -se --arg alias "$alias" '
    [.[] | select(.config["user.dotfiles.dev.platform"] == $alias)] |
    length == 1 and .[0].config["limits.cpu"] == "4" and
    .[0].config["limits.memory"] == "8GiB" and .[0].devices.root.size == "40GiB"' \
    "$TEST_DEV_STATE"/vm-*.json >/dev/null || fail "platform/resource selection failed for $alias"
done
[[ $(grep -c '^init ' "$TEST_DEV_LOG") == 4 ]] || fail 'four aliases did not create exactly four VMs'

cat >>"$checkout/release.env" <<'EOF'
PLATFORM_ALIASES[fixture]=debian-13-x86_64
LXD_IMAGES[debian-13-x86_64]=images:fixture/debian/cloud
DEFAULT_DEV_PLATFORM=fixture
EOF
run_dev >"$test_root/configured-default.log" 2>&1
jq -se '
  [.[] | select(.config["user.dotfiles.dev.platform"] == "fixture")] |
  length == 1 and .[0].image == "images:fixture/debian/cloud"' \
  "$TEST_DEV_STATE"/vm-*.json >/dev/null || fail 'release.env did not control the VM alias, image and default'
cp "$test_root/dev-config.env" "$checkout/release.env"

for invalid in 'unknown' 'debian13 ubuntu2404' 'debian13; touch unsafe'; do
  : >"$TEST_DEV_LOG"
  if run_dev -- "$invalid" >"$test_root/invalid.log" 2>&1; then
    fail 'invalid platform was accepted'
  fi
  [[ ! -s $TEST_DEV_LOG ]] || fail 'invalid platform touched LXD'
done
: >"$TEST_DEV_LOG"
if run_dev DEV_CPUS=0 >"$test_root/resources.log" 2>&1; then
  fail 'invalid resources were accepted'
fi
[[ ! -s $TEST_DEV_LOG ]] || fail 'invalid resources touched LXD'

state=$TEST_DEV_STATE/vm-$vm.json
jq '.devices.checkout.source = "/unexpected"' "$state" >"$state.next"
mv "$state.next" "$state"
if run_dev >"$test_root/unexpected.log" 2>&1; then
  fail 'an unexpected checkout mount was reused'
fi
grep -F 'unexpected type or checkout mount' "$test_root/unexpected.log" >/dev/null || fail 'unsafe reuse lacked an explanation'

export TEST_DEV_STATE=$test_root/cold-state TEST_DEV_COLD_IMAGE=1
mkdir -p "$TEST_DEV_STATE" "$test_root/downloads"
checksum=$(printf 'fixture qcow2\n' | sha256sum)
export PLATFORM_ALIAS=amazonlinux2023 DEV_PROJECT=fixture DEV_NETWORK=fixture-net DEV_STORAGE=fixture-pool
export DEV_CPUS=2 DEV_MEMORY=4GiB DEV_DISK=20GiB
printf '%s\n' \
  'LXD_IMAGES[amzn-2023-x86_64]=https://fixture.invalid/image.qcow2' \
  "LXD_IMAGE_SHA256[amzn-2023-x86_64]=${checksum%% *}" >>"$checkout/release.env"
TMPDIR="$test_root/downloads" bash "$checkout/scripts/dev-vm" >"$test_root/import.log" 2>&1
[[ -s $TEST_DEV_STATE/image.json && -s $TEST_DEV_STATE/cloud-init.yaml ]] || fail 'official QCOW2 image did not import and bootstrap its agent'
[[ -z $(find "$test_root/downloads" -mindepth 1 -print -quit) ]] || fail 'successful import leaked temporary downloads'
export TEST_DEV_STATE=$test_root/bad-checksum-state
mkdir -p "$TEST_DEV_STATE"
printf '%s\n' 'LXD_IMAGE_SHA256[amzn-2023-x86_64]=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
  >>"$checkout/release.env"
: >"$TEST_DEV_LOG"
if TMPDIR="$test_root/downloads" bash "$checkout/scripts/dev-vm" >"$test_root/checksum.log" 2>&1; then
  fail 'corrupt QCOW2 image was accepted'
fi
if grep -qE '^(init|image import) ' "$TEST_DEV_LOG"; then
  fail 'corrupt image was imported or started'
fi
[[ -z $(find "$test_root/downloads" -mindepth 1 -print -quit) ]] || fail 'failed import leaked temporary downloads'

printf 'LXD_IMAGE_SHA256[amzn-2023-x86_64]=%s\n' "${checksum%% *}" >>"$checkout/release.env"
TEST_DEV_STATE="$test_root/cold-state" TEST_DEV_AGENT_HANG=1 timeout --kill-after=5s 25s \
  bash "$checkout/scripts/dev-vm" >"$test_root/agent-retry.log" 2>&1 ||
  fail 'initial agent connection ignored its timeout and blocked VM entry'

printf 'dev_vm: tests passed\n'
