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

create_release_repo() {
  local destination=$1
  local label=$2

  mkdir -p "$destination/nvim2/.config/nvim2/tests"
  cat >"$destination/bstow" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
repo=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
target=$HOME
operation=
dry_run=0
while (($#)); do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --force) ;;
    -t) shift; target=$1 ;;
    stow | unstow) operation=$1 ;;
  esac
  shift
done
[[ -n $operation ]]
init_source=$repo/nvim2/.config/nvim2/init.lua
tests_source=$repo/nvim2/.config/nvim2/tests
init_target=$target/.config/nvim2/init.lua
tests_target=$target/.config/nvim2/tests
((dry_run)) && exit 0
mkdir -p "$target/.config/nvim2"
if [[ $operation == stow ]]; then
  ln -sfn "$init_source" "$init_target"
  ln -sfn "$tests_source" "$tests_target"
else
  if [[ -L $init_target && $(readlink -f -- "$init_target") == "$init_source" ]]; then
    unlink "$init_target"
  fi
  if [[ -L $tests_target && $(readlink -f -- "$tests_target") == "$tests_source" ]]; then
    unlink "$tests_target"
  fi
fi
EOF
  chmod +x "$destination/bstow"
  printf 'return %q\n' "$label" >"$destination/nvim2/.config/nvim2/init.lua"
cat >"$destination/nvim2/.config/nvim2/tests/check.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ ${NVIM2_CHECK_TOOLS:-} == 1 ]]
[[ ${NVIM2_RELEASE_TEST_FAIL_CHECK:-0} != 1 ]]
"$HOME/bin/nvim" --version >/dev/null
"$HOME/bin/node" --version >/dev/null
"$HOME/bin/rg" --version >/dev/null
EOF
  chmod +x "$destination/nvim2/.config/nvim2/tests/check.sh"
}

create_release_artifact() {
  local destination=$1
  local label=$2
  local release_id=$3
  local build=$test_root/build-$label
  local source=$test_root/source-$label
  local commit
  local python_path
  local python_version

  mkdir -p "$destination" "$build/nvim-linux-x86_64/bin" \
    "$build/node-v1.0.0-linux-x64/bin" \
    "$build/node-v1.0.0-linux-x64/lib/node_modules/npm/bin" \
    "$build/node-v1.0.0-linux-x64/lib/node_modules/corepack/dist" \
    "$build/ripgrep-1.0.0-x86_64-unknown-linux-musl" \
    "$build/data/mason/bin"
  cat >"$build/nvim-linux-x86_64/bin/nvim" <<'EOF'
#!/usr/bin/env bash
printf 'NVIM v1.0.0\n'
EOF
  chmod +x "$build/nvim-linux-x86_64/bin/nvim"
  for command_name in node npm-cli npx-cli corepack; do
    case "$command_name" in
      node) command_path="$build/node-v1.0.0-linux-x64/bin/node" ;;
      npm-cli | npx-cli) command_path="$build/node-v1.0.0-linux-x64/lib/node_modules/npm/bin/$command_name.js" ;;
      corepack) command_path="$build/node-v1.0.0-linux-x64/lib/node_modules/corepack/dist/corepack.js" ;;
    esac
    cat >"$command_path" <<EOF
#!/usr/bin/env bash
printf '$command_name v1.0.0\\n'
EOF
    chmod +x "$command_path"
  done
  ln -s ../lib/node_modules/npm/bin/npm-cli.js "$build/node-v1.0.0-linux-x64/bin/npm"
  ln -s ../lib/node_modules/npm/bin/npx-cli.js "$build/node-v1.0.0-linux-x64/bin/npx"
  ln -s ../lib/node_modules/corepack/dist/corepack.js "$build/node-v1.0.0-linux-x64/bin/corepack"
  cat >"$build/ripgrep-1.0.0-x86_64-unknown-linux-musl/rg" <<'EOF'
#!/usr/bin/env bash
printf 'ripgrep 1.0.0\n'
EOF
  chmod +x "$build/ripgrep-1.0.0-x86_64-unknown-linux-musl/rg"
  cat >"$build/data/mason/bin/lua-language-server" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$build/data/mason/bin/lua-language-server"
  printf '%s\n' "$label" >"$build/data/plugin-version"
  tar -czf "$destination/nvim-linux-x86_64.tar.gz" \
    -C "$build" nvim-linux-x86_64
  tar -cJf "$destination/node-v1.0.0-linux-x64.tar.xz" \
    -C "$build" node-v1.0.0-linux-x64
  tar -czf "$destination/ripgrep-1.0.0-x86_64-unknown-linux-musl.tar.gz" \
    -C "$build" ripgrep-1.0.0-x86_64-unknown-linux-musl
  tar -czf "$destination/nvim2-data.tar.gz" -C "$build/data" .

  create_release_repo "$source" "$label"
  git -C "$source" init -q
  git -C "$source" config user.name test
  git -C "$source" config user.email test@example.invalid
  git -C "$source" add .
  git -C "$source" commit -qm "$label"
  commit=$(git -C "$source" rev-parse HEAD)
  git -C "$source" bundle create "$destination/dotfiles.bundle" HEAD
  python_path=$test_python
  python_version=$("$test_python" -c \
    'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
  cat >"$destination/release.env" <<EOF
RELEASE_ID=$release_id
PLATFORM_ID=$test_platform
DOTFILES_COMMIT=$commit
NVIM_VERSION=v1.0.0
NVIM_ARCHIVE=nvim-linux-x86_64.tar.gz
NODE_VERSION=1.0.0
NODE_ARCHIVE=node-v1.0.0-linux-x64.tar.xz
RG_VERSION=1.0.0
RG_ARCHIVE=ripgrep-1.0.0-x86_64-unknown-linux-musl.tar.gz
TARGET_USER=$(id -un)
TARGET_UID=$(id -u)
TARGET_HOME=$release_home
PYTHON_PATH=$python_path
PYTHON_VERSION=$python_version
EOF
  (
    cd "$destination"
    sha256sum dotfiles.bundle node-v1.0.0-linux-x64.tar.xz \
      nvim-linux-x86_64.tar.gz nvim2-data.tar.gz release.env \
      ripgrep-1.0.0-x86_64-unknown-linux-musl.tar.gz >SHA256SUMS
  )
}

# shellcheck disable=SC1091
source /etc/os-release
case "$ID:$VERSION_ID" in
  debian:13) test_platform=debian-13-x86_64 ;;
  ubuntu:24.04) test_platform=ubuntu-24.04-x86_64 ;;
  ubuntu:26.04) test_platform=ubuntu-26.04-x86_64 ;;
  amzn:2023) test_platform=amzn-2023-x86_64 ;;
  *) fail "unsupported test platform: $ID $VERSION_ID" ;;
esac
release_home=$test_root/release-home
release_artifact_one=$test_root/release-artifact-one
release_artifact_two=$test_root/release-artifact-two
mkdir -p "$release_home/bin" "$release_home/.local/share/nvim2" \
  "$release_home/.local/state" "$release_home/bin/nvim-v0/bin" \
  "$release_home/bin/nodejs-0/bin"
test_python=$(python3 -c 'import os, sys; print(os.path.realpath(sys.executable))')
ln -s "$test_python" "$release_home/bin/python3"
ln -s "$test_python" "$release_home/bin/python"
cat >"$release_home/bin/nvim-v0/bin/nvim" <<'EOF'
#!/usr/bin/env bash
printf 'previous-nvim\n'
EOF
chmod +x "$release_home/bin/nvim-v0/bin/nvim"
ln -s nvim-v0/bin/nvim "$release_home/bin/nvim"
for command_name in node npm npx corepack; do
  cat >"$release_home/bin/nodejs-0/bin/$command_name" <<EOF
#!/usr/bin/env bash
printf 'previous-$command_name\\n'
EOF
  chmod +x "$release_home/bin/nodejs-0/bin/$command_name"
  ln -s "nodejs-0/bin/$command_name" "$release_home/bin/$command_name"
done
cat >"$release_home/bin/rg-0" <<'EOF'
#!/usr/bin/env bash
printf 'previous-rg\n'
EOF
chmod +x "$release_home/bin/rg-0"
ln -s rg-0 "$release_home/bin/rg"
printf 'previous-data\n' >"$release_home/.local/share/nvim2/marker"
previous_repo=$release_home/previous-repo
create_release_repo "$previous_repo" previous
HOME=$release_home "$previous_repo/bstow" -t "$release_home" stow nvim2
create_release_artifact "$release_artifact_one" plugin-one nvim2-release-one
create_release_artifact "$release_artifact_two" plugin-two nvim2-release-two

previous_nvim_link=$(readlink -- "$release_home/bin/nvim")
previous_nvim_hash=$(sha256sum "$release_home/bin/nvim-v0/bin/nvim")
previous_data_hash=$(sha256sum "$release_home/.local/share/nvim2/marker")
broken_artifact=$test_root/release-artifact-broken
cp -a "$release_artifact_one" "$broken_artifact"
printf 'not a gzip archive\n' >"$broken_artifact/nvim-linux-x86_64.tar.gz"
(
  cd "$broken_artifact"
  sha256sum dotfiles.bundle node-v1.0.0-linux-x64.tar.xz \
    nvim-linux-x86_64.tar.gz nvim2-data.tar.gz release.env \
    ripgrep-1.0.0-x86_64-unknown-linux-musl.tar.gz >SHA256SUMS
)
expect_failure 'failed to extract nvim-linux-x86_64.tar.gz' env HOME="$release_home" \
  bash "$repo_dir/scripts/nvim2-release" install "$broken_artifact"
[[ $(readlink -- "$release_home/bin/nvim") == "$previous_nvim_link" ]]
[[ $(sha256sum "$release_home/bin/nvim-v0/bin/nvim") == "$previous_nvim_hash" ]]
[[ $(sha256sum "$release_home/.local/share/nvim2/marker") == "$previous_data_hash" ]]
[[ -z $(find "$release_home" -name '*.stage.*' -print -quit) ]] ||
  fail 'failed extraction left staging paths behind'

unlink "$release_home/bin/nvim"
printf 'foreign\n' >"$release_home/foreign-nvim"
ln -s ../foreign-nvim "$release_home/bin/nvim"
expect_failure 'refusing unmanaged link' env HOME="$release_home" \
  bash "$repo_dir/scripts/nvim2-release" install "$release_artifact_one"
[[ $(readlink -- "$release_home/bin/nvim") == ../foreign-nvim ]]
[[ $(<"$release_home/foreign-nvim") == foreign ]]
unlink "$release_home/bin/nvim"
ln -s "$previous_nvim_link" "$release_home/bin/nvim"

expect_failure 'activation failed with status 1; previous release restored' \
  env HOME="$release_home" NVIM2_RELEASE_TEST_FAIL_CHECK=1 \
  bash "$repo_dir/scripts/nvim2-release" install "$release_artifact_one"
[[ ! -e $release_home/.local/state/nvim2-release-rollback.env ]]
[[ -d $release_home/.local/share/nvim2 && ! -L $release_home/.local/share/nvim2 ]]
[[ $(sha256sum "$release_home/.local/share/nvim2/marker") == "$previous_data_hash" ]]
[[ $("$release_home/bin/nvim") == previous-nvim ]]
for command_name in node npm npx corepack; do
  [[ $("$release_home/bin/$command_name") == "previous-$command_name" ]]
done
[[ $("$release_home/bin/rg") == previous-rg ]]
[[ $(readlink -f -- "$release_home/.config/nvim2/init.lua") == \
  "$previous_repo/nvim2/.config/nvim2/init.lua" ]]
[[ -z $(find "$release_home" -name '*.stage.*' -print -quit) ]] ||
  fail 'failed activation left staging paths behind'

HOME=$release_home bash "$repo_dir/scripts/nvim2-release" install "$release_artifact_one"
[[ $(<"$release_home/.local/share/nvim2/plugin-version") == plugin-one ]]
[[ $("$release_home/bin/nvim" --version) == 'NVIM v1.0.0' ]]
[[ $(<"$release_home/.local/share/nvim2/.nvim2-release-artifact.sha256") == \
  "$(sha256sum "$release_artifact_one/nvim2-data.tar.gz" | cut -d ' ' -f 1)" ]]
printf 'runtime cache\n' >"$release_home/.local/share/nvim2/runtime-cache"
HOME=$release_home bash "$repo_dir/scripts/nvim2-release" install "$release_artifact_one"
[[ $(<"$release_home/.local/share/nvim2/runtime-cache") == 'runtime cache' ]]
HOME=$release_home bash "$repo_dir/scripts/nvim2-release" rollback
[[ -d $release_home/.local/share/nvim2 && ! -L $release_home/.local/share/nvim2 ]]
[[ $(sha256sum "$release_home/.local/share/nvim2/marker") == "$previous_data_hash" ]]
[[ $(readlink -- "$release_home/bin/nvim") == "$previous_nvim_link" ]]
[[ $("$release_home/bin/nvim") == previous-nvim ]]
[[ $(readlink -f -- "$release_home/.config/nvim2/init.lua") == \
  "$previous_repo/nvim2/.config/nvim2/init.lua" ]]

HOME=$release_home bash "$repo_dir/scripts/nvim2-release" install "$release_artifact_one"
runtime_inode=$(stat -c %i "$release_home/bin/nvim-v1.0.0/bin/nvim")
HOME=$release_home bash "$repo_dir/scripts/nvim2-release" install "$release_artifact_two"
[[ $(stat -c %i "$release_home/bin/nvim-v1.0.0/bin/nvim") == "$runtime_inode" ]]
[[ $(<"$release_home/.local/share/nvim2/plugin-version") == plugin-two ]]
HOME=$release_home bash "$repo_dir/scripts/nvim2-release" rollback
[[ $(<"$release_home/.local/share/nvim2/plugin-version") == plugin-one ]]
[[ $("$release_home/bin/nvim" --version) == 'NVIM v1.0.0' ]]

printf 'Nvim2 release tests passed\n'
