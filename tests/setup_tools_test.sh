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

assert_link() {
  local path=$1
  local target=$2
  [[ -L $path ]] || fail "$path is not a link"
  [[ $(readlink -- "$path") == "$target" ]] || fail "$path has the wrong target"
}

write_fake() {
  local path=$1
  local name=$2
  local version=${3#v}

  mkdir -p "$(dirname -- "$path")"
  cat >"$path" <<EOF
#!/usr/bin/env bash
printf '%s\\n' '$name $version'
EOF
  chmod 0755 "$path"
}

make_test_repo() {
  local destination=$1

  mkdir -p "$destination/scripts"
  cp "$repo_dir/setup-tools" "$destination/setup-tools"
  cp "$repo_dir/scripts/setup-lib" "$destination/scripts/setup-lib"
  cp "$repo_dir/versions.env" "$destination/versions.env"
  cp "$repo_dir/validation.env" "$destination/validation.env"
}

make_archives() {
  local repository=$1
  local archive_root=$2
  local work=$test_root/archive-work
  local digest

  # shellcheck source=../versions.env
  source "$repository/versions.env"
  mkdir -p "$archive_root" "$work"

  write_fake "$work/gh_${GH_VERSION}_linux_amd64/bin/gh" gh "$GH_VERSION"
  mkdir -p "$archive_root/gh/$GH_VERSION"
  tar -C "$work" -czf "$archive_root/gh/$GH_VERSION/gh_${GH_VERSION}_linux_amd64.tar.gz" \
    "gh_${GH_VERSION}_linux_amd64"
  digest=$(sha256sum "$archive_root/gh/$GH_VERSION/gh_${GH_VERSION}_linux_amd64.tar.gz" | awk '{print $1}')
  printf 'GH_SHA256=%s\n' "$digest" >>"$repository/versions.env"

  write_fake "$work/k9s" k9s "$K9S_VERSION"
  mkdir -p "$archive_root/k9s/$K9S_VERSION"
  tar -C "$work" -czf "$archive_root/k9s/$K9S_VERSION/k9s_Linux_amd64.tar.gz" k9s
  digest=$(sha256sum "$archive_root/k9s/$K9S_VERSION/k9s_Linux_amd64.tar.gz" | awk '{print $1}')
  printf 'K9S_SHA256=%s\n' "$digest" >>"$repository/versions.env"

  write_fake "$archive_root/oh-my-posh/$OMP_VERSION/posh-linux-amd64" oh-my-posh "$OMP_VERSION"
  digest=$(sha256sum "$archive_root/oh-my-posh/$OMP_VERSION/posh-linux-amd64" | awk '{print $1}')
  printf 'OMP_SHA256=%s\n' "$digest" >>"$repository/versions.env"

  write_fake "$work/uv-x86_64-unknown-linux-gnu/uv" uv "$UV_VERSION"
  write_fake "$work/uv-x86_64-unknown-linux-gnu/uvx" uvx "$UV_VERSION"
  mkdir -p "$archive_root/uv/$UV_VERSION"
  tar -C "$work" -czf "$archive_root/uv/$UV_VERSION/uv-x86_64-unknown-linux-gnu.tar.gz" \
    uv-x86_64-unknown-linux-gnu
  digest=$(sha256sum "$archive_root/uv/$UV_VERSION/uv-x86_64-unknown-linux-gnu.tar.gz" | awk '{print $1}')
  printf 'UV_SHA256=%s\n' "$digest" >>"$repository/versions.env"

  write_fake "$work/nvim-linux-x86_64/bin/nvim" nvim "$NVIM_VERSION"
  mkdir -p "$work/nvim-linux-x86_64/share/nvim/runtime/syntax"
  printf 'runtime fixture\n' >"$work/nvim-linux-x86_64/share/nvim/runtime/syntax/test.vim"
  mkdir -p "$archive_root/nvim/$NVIM_VERSION"
  tar -C "$work" -czf "$archive_root/nvim/$NVIM_VERSION/nvim-linux-x86_64.tar.gz" \
    nvim-linux-x86_64
  digest=$(sha256sum "$archive_root/nvim/$NVIM_VERSION/nvim-linux-x86_64.tar.gz" | awk '{print $1}')
  printf 'NVIM_SHA256=%s\n' "$digest" >>"$repository/versions.env"
}

test_repository="$test_root/repository"
archive_root="$test_root/archive files"
test_home="$test_root/home"
make_test_repo "$test_repository"
make_archives "$test_repository" "$archive_root"

mkdir -p "$test_root/shim"
cat >"$test_root/shim/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl must not run during local import\n' >&2
exit 99
EOF
chmod 0755 "$test_root/shim/curl"

mkdir -p "$test_home"
printf 'private context bytes' >"$test_home/kube-backup-contexts.txt"
printf 'private prefix bytes' >"$test_home/kube-log-prefixes.txt"
cp "$test_home/kube-backup-contexts.txt" "$test_root/kube-context-before"
cp "$test_home/kube-log-prefixes.txt" "$test_root/kube-prefix-before"
test_xdg=$test_root/'xdg elsewhere'

before=$(find "$archive_root" -type f -print0 | sort -z | xargs -0 sha256sum)
HOME="$test_home" XDG_CONFIG_HOME="$test_xdg" PATH="$test_root/shim:$PATH" \
  "$test_repository/setup-tools" --from "$archive_root" \
  k9s gh oh-my-posh uv nvim
after=$(find "$archive_root" -type f -print0 | sort -z | xargs -0 sha256sum)
[[ $before == "$after" ]] || fail 'local import changed an input file'
cmp "$test_root/kube-context-before" "$test_home/kube-backup-contexts.txt" ||
  fail 'setup-tools changed kube-backup-contexts.txt'
cmp "$test_root/kube-prefix-before" "$test_home/kube-log-prefixes.txt" ||
  fail 'setup-tools changed kube-log-prefixes.txt'
[[ ! -e $test_xdg/kube-backup-contexts.txt &&
  ! -e $test_xdg/kube-log-prefixes.txt ]] ||
  fail 'setup-tools relocated private Kubernetes inputs into XDG_CONFIG_HOME'

# shellcheck source=../versions.env
source "$test_repository/versions.env"
assert_link "$test_home/bin/k9s" "k9s-$K9S_VERSION"
assert_link "$test_home/bin/gh" "gh-$GH_VERSION"
assert_link "$test_home/bin/oh-my-posh" "oh-my-posh-$OMP_VERSION"
assert_link "$test_home/bin/uv" "uv-$UV_VERSION"
assert_link "$test_home/bin/uvx" "uvx-$UV_VERSION"
assert_link "$test_home/bin/nvim" "nvim-$NVIM_VERSION/bin/nvim"
[[ -f $test_home/bin/nvim-$NVIM_VERSION/share/nvim/runtime/syntax/test.vim ]] ||
  fail 'Neovim runtime tree was not retained'
"$test_home/bin/k9s" --version | grep -F "$K9S_VERSION" >/dev/null
"$test_home/bin/uvx" --version | grep -F "$UV_VERSION" >/dev/null

find "$archive_root" -depth -delete
HOME="$test_home" XDG_CONFIG_HOME="$test_xdg" PATH="$test_root/shim:$PATH" \
  "$test_repository/setup-tools" --from "$archive_root" k9s gh uv nvim
cmp "$test_root/kube-context-before" "$test_home/kube-backup-contexts.txt" ||
  fail 'setup-tools reconciliation changed kube-backup-contexts.txt'
cmp "$test_root/kube-prefix-before" "$test_home/kube-log-prefixes.txt" ||
  fail 'setup-tools reconciliation changed kube-log-prefixes.txt'

set +e
missing_output=$(HOME="$test_root/missing-home" "$test_repository/setup-tools" \
  --from "$test_root/missing archive" k9s 2>&1)
missing_status=$?
set -e
[[ $missing_status -ne 0 ]] || fail 'missing local archive was accepted'
[[ $missing_output == *"$test_root/missing archive/k9s/$K9S_VERSION/k9s_Linux_amd64.tar.gz"* ]] ||
  fail 'missing local archive did not report its exact path'

failure_repo="$test_root/failure-repository"
failure_archives="$test_root/failure-archives"
failure_home="$test_root/failure-home"
make_test_repo "$failure_repo"
make_archives "$failure_repo" "$failure_archives"
HOME="$failure_home" "$failure_repo/setup-tools" --from "$failure_archives" k9s
old_target=$(readlink -- "$failure_home/bin/k9s")
write_fake "$failure_archives/k9s/0.51.1/k9s_Linux_amd64.tar.gz" k9s 0.51.1
cat >>"$failure_repo/versions.env" <<'EOF'
K9S_VERSION=0.51.1
K9S_SHA256=0000000000000000000000000000000000000000000000000000000000000000
EOF
set +e
HOME="$failure_home" "$failure_repo/setup-tools" --from "$failure_archives" k9s >/dev/null 2>&1
checksum_status=$?
set -e
[[ $checksum_status -ne 0 ]] || fail 'bad checksum was accepted'
[[ $(readlink -- "$failure_home/bin/k9s") == "$old_target" ]] ||
  fail 'checksum failure changed the selected version'
[[ ! -e $failure_home/bin/k9s-0.51.1 ]] || fail 'checksum failure installed a candidate'

recovery_repo="$test_root/recovery-repository"
recovery_archives="$test_root/recovery-archives"
recovery_home="$test_root/recovery-home"
make_test_repo "$recovery_repo"
make_archives "$recovery_repo" "$recovery_archives"
mkdir -p "$test_root/fail-bin"
cat >"$test_root/fail-bin/mv" <<'EOF'
#!/usr/bin/env bash
set -eu
args="$*"
source_path=
for argument in "$@"; do
  case $argument in -- | -*) ;; *) source_path=$argument; break ;; esac
done
if [ -n "$source_path" ] && [ -f "$source_path" ] &&
  grep -q '^complete' "$source_path" && [ ! -e "$TEST_MV_MARKER" ]; then
  : >"$TEST_MV_MARKER"
  exit 73
fi
exec "$TEST_REAL_MV" "$@"
EOF
chmod 0755 "$test_root/fail-bin/mv"
real_mv=$(command -v mv)
set +e
HOME="$recovery_home" PATH="$test_root/fail-bin:$PATH" \
  TEST_REAL_MV="$real_mv" TEST_MV_MARKER="$test_root/mv-failed" \
  "$recovery_repo/setup-tools" --from "$recovery_archives" k9s >/dev/null 2>&1
publish_status=$?
set -e
[[ $publish_status -eq 73 ]] || fail 'state publication fixture returned an unexpected status'
[[ -f $recovery_home/bin/k9s-$K9S_VERSION ]] || fail 'failed publication lost installed content'
[[ ! -L $recovery_home/bin/k9s ]] || fail 'failed publication changed the selection'
find "$recovery_archives" -depth -delete
HOME="$recovery_home" "$recovery_repo/setup-tools" \
  --from "$recovery_archives" k9s
assert_link "$recovery_home/bin/k9s" "k9s-$K9S_VERSION"

pair_repo="$test_root/pair-repository"
pair_archives="$test_root/pair-archives"
pair_home="$test_root/pair-home"
pair_work="$test_root/pair-work"
make_test_repo "$pair_repo"
make_archives "$pair_repo" "$pair_archives"
HOME="$pair_home" "$pair_repo/setup-tools" --from "$pair_archives" uv
old_uv_target=$(readlink -- "$pair_home/bin/uv")
old_uvx_target=$(readlink -- "$pair_home/bin/uvx")
new_uv_version=0.12.20
write_fake "$pair_work/uv-x86_64-unknown-linux-gnu/uv" uv "$new_uv_version"
write_fake "$pair_work/uv-x86_64-unknown-linux-gnu/uvx" uvx "$new_uv_version"
mkdir -p "$pair_archives/uv/$new_uv_version"
tar -C "$pair_work" -czf \
  "$pair_archives/uv/$new_uv_version/uv-x86_64-unknown-linux-gnu.tar.gz" \
  uv-x86_64-unknown-linux-gnu
new_uv_digest=$(sha256sum \
  "$pair_archives/uv/$new_uv_version/uv-x86_64-unknown-linux-gnu.tar.gz" | awk '{print $1}')
cat >>"$pair_repo/versions.env" <<EOF
UV_VERSION=$new_uv_version
UV_SHA256=$new_uv_digest
EOF
mkdir -p "$test_root/activation-fail-bin"
cat >"$test_root/activation-fail-bin/mv" <<'EOF'
#!/usr/bin/env bash
set -eu
source_path=
for argument in "$@"; do
  case $argument in -- | -*) ;; *) source_path=$argument; break ;; esac
done
case $source_path in
  */.uvx.link.*)
    if [ ! -e "$TEST_MV_MARKER" ]; then
      : >"$TEST_MV_MARKER"
      exit 74
    fi
    ;;
esac
exec "$TEST_REAL_MV" "$@"
EOF
chmod 0755 "$test_root/activation-fail-bin/mv"
set +e
HOME="$pair_home" PATH="$test_root/activation-fail-bin:$PATH" \
  TEST_REAL_MV="$real_mv" TEST_MV_MARKER="$test_root/activation-mv-failed" \
  "$pair_repo/setup-tools" --from "$pair_archives" uv >/dev/null 2>&1
activation_status=$?
set -e
[[ $activation_status -eq 74 ]] || fail 'activation fixture returned an unexpected status'
assert_link "$pair_home/bin/uv" "$old_uv_target"
assert_link "$pair_home/bin/uvx" "$old_uvx_target"

mkdir -p "$failure_home/.local/state/dotfiles/setup-tools/locks/k9s.lock"
set +e
lock_output=$(HOME="$failure_home" "$failure_repo/setup-tools" \
  --from "$failure_archives" k9s 2>&1)
lock_status=$?
set -e
[[ $lock_status -ne 0 ]] || fail 'concurrent setup lock was ignored'
[[ $lock_output == *'another setup-tools process owns k9s'* ]] ||
  fail 'concurrent setup did not report its lock owner'

printf 'changed\n' >>"$recovery_home/bin/k9s-$K9S_VERSION"
set +e
modified_output=$(HOME="$recovery_home" "$recovery_repo/setup-tools" \
  --from "$recovery_archives" k9s 2>&1)
modified_status=$?
set -e
[[ $modified_status -ne 0 ]] || fail 'modified retained installation was accepted'
[[ $modified_output == *'managed installation was modified'* ]] ||
  fail 'modified retained installation did not report a conflict'

printf 'Setup tools tests passed\n'
