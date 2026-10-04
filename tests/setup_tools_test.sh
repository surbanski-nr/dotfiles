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

append_release() {
  local file=$1 catalog=$2 tool=$3 version=$4 url=$5 digest=$6 value

  value=$'\n'"$version|$url|$digest"$'\n'
  printf '%s[%q]=%q\n' "$catalog" "$tool" "$value" >>"$file"
}

load_test_versions() {
  local repository=$1

  # shellcheck disable=SC1090
  source "$repository/validation.env"
  # shellcheck disable=SC1090
  source "$repository/versions.env"
  # shellcheck disable=SC1090
  source "$repository/scripts/setup-lib"
  setup_release_first TOOL_RELEASES gh; GH_VERSION=$RELEASE_VERSION
  setup_release_first TOOL_RELEASES k9s; K9S_VERSION=$RELEASE_VERSION
  setup_release_first TOOL_RELEASES oh-my-posh; OMP_VERSION=$RELEASE_VERSION
  setup_release_first TOOL_RELEASES uv; UV_VERSION=$RELEASE_VERSION
  setup_release_first TOOL_RELEASES nvim; NVIM_VERSION=$RELEASE_VERSION
  setup_release_first TOOL_RELEASES tmux; TMUX_VERSION=$RELEASE_VERSION
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

  load_test_versions "$repository"
  mkdir -p "$archive_root" "$work"

  write_fake "$work/gh_${GH_VERSION}_linux_amd64/bin/gh" gh "$GH_VERSION"
  mkdir -p "$archive_root/gh/$GH_VERSION"
  tar -C "$work" -czf "$archive_root/gh/$GH_VERSION/gh_${GH_VERSION}_linux_amd64.tar.gz" \
    "gh_${GH_VERSION}_linux_amd64"
  digest=$(sha256sum "$archive_root/gh/$GH_VERSION/gh_${GH_VERSION}_linux_amd64.tar.gz" | awk '{print $1}')
  append_release "$repository/versions.env" TOOL_RELEASES gh "$GH_VERSION" \
    "https://example.invalid/gh_${GH_VERSION}_linux_amd64.tar.gz" "$digest"

  write_fake "$work/k9s" k9s "$K9S_VERSION"
  mkdir -p "$archive_root/k9s/$K9S_VERSION"
  tar -C "$work" -czf "$archive_root/k9s/$K9S_VERSION/k9s_Linux_amd64.tar.gz" k9s
  digest=$(sha256sum "$archive_root/k9s/$K9S_VERSION/k9s_Linux_amd64.tar.gz" | awk '{print $1}')
  append_release "$repository/versions.env" TOOL_RELEASES k9s "$K9S_VERSION" \
    https://example.invalid/k9s_Linux_amd64.tar.gz "$digest"

  write_fake "$archive_root/oh-my-posh/$OMP_VERSION/posh-linux-amd64" oh-my-posh "$OMP_VERSION"
  digest=$(sha256sum "$archive_root/oh-my-posh/$OMP_VERSION/posh-linux-amd64" | awk '{print $1}')
  append_release "$repository/versions.env" TOOL_RELEASES oh-my-posh "$OMP_VERSION" \
    https://example.invalid/posh-linux-amd64 "$digest"

  write_fake "$work/uv-x86_64-unknown-linux-gnu/uv" uv "$UV_VERSION"
  write_fake "$work/uv-x86_64-unknown-linux-gnu/uvx" uvx "$UV_VERSION"
  mkdir -p "$archive_root/uv/$UV_VERSION"
  tar -C "$work" -czf "$archive_root/uv/$UV_VERSION/uv-x86_64-unknown-linux-gnu.tar.gz" \
    uv-x86_64-unknown-linux-gnu
  digest=$(sha256sum "$archive_root/uv/$UV_VERSION/uv-x86_64-unknown-linux-gnu.tar.gz" | awk '{print $1}')
  append_release "$repository/versions.env" TOOL_RELEASES uv "$UV_VERSION" \
    https://example.invalid/uv-x86_64-unknown-linux-gnu.tar.gz "$digest"

  write_fake "$work/nvim-linux-x86_64/bin/nvim" nvim "$NVIM_VERSION"
  mkdir -p "$work/nvim-linux-x86_64/share/nvim/runtime/syntax"
  printf 'runtime fixture\n' >"$work/nvim-linux-x86_64/share/nvim/runtime/syntax/test.vim"
  mkdir -p "$archive_root/nvim/$NVIM_VERSION"
  tar -C "$work" -czf "$archive_root/nvim/$NVIM_VERSION/nvim-linux-x86_64.tar.gz" \
    nvim-linux-x86_64
  digest=$(sha256sum "$archive_root/nvim/$NVIM_VERSION/nvim-linux-x86_64.tar.gz" | awk '{print $1}')
  append_release "$repository/versions.env" TOOL_RELEASES nvim "$NVIM_VERSION" \
    https://example.invalid/nvim-linux-x86_64.tar.gz "$digest"
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

load_test_versions "$test_repository"
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

set +e
empty_from_output=$(HOME="$test_root/empty-from-home" PATH="$test_root/shim:$PATH" \
  "$test_repository/setup-tools" --from '' k9s 2>&1)
empty_from_status=$?
set -e
[[ $empty_from_status -ne 0 ]] || fail 'empty --from directory was accepted'
[[ $empty_from_output == *'--from requires a nonempty directory'* ]] ||
  fail 'empty --from directory did not report an argument error'
[[ $empty_from_output != *'curl must not run'* ]] || fail 'empty --from attempted a download'
[[ ! -e $test_root/empty-from-home/bin && ! -e $test_root/empty-from-home/.local ]] ||
  fail 'empty --from changed the target home'

set +e
repeated_from_output=$(HOME="$test_root/repeated-from-home" PATH="$test_root/shim:$PATH" \
  "$test_repository/setup-tools" --from "$archive_root" --from "$archive_root" k9s 2>&1)
repeated_from_status=$?
set -e
[[ $repeated_from_status -ne 0 ]] || fail 'repeated --from option was accepted'
[[ $repeated_from_output == *'--from may be supplied only once'* ]] ||
  fail 'repeated --from option did not report an argument error'
[[ ! -e $test_root/repeated-from-home/bin && ! -e $test_root/repeated-from-home/.local ]] ||
  fail 'repeated --from changed the target home'

foreign_home=$test_root/foreign-home
mkdir -p "$foreign_home/bin"
write_fake "$foreign_home/bin/k9s-manual" k9s manual
ln -s k9s-manual "$foreign_home/bin/k9s"
foreign_hash=$(sha256sum "$foreign_home/bin/k9s-manual")
set +e
foreign_output=$(HOME="$foreign_home" "$test_repository/setup-tools" \
  --from "$archive_root" k9s 2>&1)
foreign_status=$?
set -e
[[ $foreign_status -ne 0 ]] || fail 'foreign version-like link was accepted'
[[ $foreign_output == *'refusing foreign link'* ]] || fail 'foreign link conflict was not reported'
assert_link "$foreign_home/bin/k9s" k9s-manual
[[ $(sha256sum "$foreign_home/bin/k9s-manual") == "$foreign_hash" ]] ||
  fail 'foreign link target was changed'

foreign_nvim_home=$test_root/foreign-nvim-home
mkdir -p "$foreign_nvim_home/bin/nvim-v999/bin"
write_fake "$foreign_nvim_home/bin/nvim-v999/bin/nvim" nvim v999
ln -s nvim-v999/bin/nvim "$foreign_nvim_home/bin/nvim"
foreign_nvim_hash=$(sha256sum "$foreign_nvim_home/bin/nvim-v999/bin/nvim")
set +e
foreign_nvim_output=$(HOME="$foreign_nvim_home" "$test_repository/setup-tools" \
  --from "$archive_root" nvim 2>&1)
foreign_nvim_status=$?
set -e
[[ $foreign_nvim_status -ne 0 ]] || fail 'foreign nvim-v* link was accepted'
[[ $foreign_nvim_output == *'refusing foreign link'* ]] ||
  fail 'foreign nvim-v* link conflict was not reported'
assert_link "$foreign_nvim_home/bin/nvim" nvim-v999/bin/nvim
[[ $(sha256sum "$foreign_nvim_home/bin/nvim-v999/bin/nvim") == "$foreign_nvim_hash" ]] ||
  fail 'foreign nvim-v* target was changed'

unsafe_repository=$test_root/unsafe-repository
unsafe_archives=$test_root/unsafe-archives
unsafe_home=$test_root/unsafe-home
unsafe_work=$test_root/unsafe-work
make_test_repo "$unsafe_repository"
load_test_versions "$unsafe_repository"
mkdir -p "$unsafe_work/nvim-linux-x86_64/bin" "$unsafe_archives/nvim/$NVIM_VERSION"
ln -s ../../../outside "$unsafe_work/nvim-linux-x86_64/bin/nvim"
tar -C "$unsafe_work" -czf \
  "$unsafe_archives/nvim/$NVIM_VERSION/nvim-linux-x86_64.tar.gz" nvim-linux-x86_64
unsafe_digest=$(sha256sum \
  "$unsafe_archives/nvim/$NVIM_VERSION/nvim-linux-x86_64.tar.gz" | awk '{print $1}')
append_release "$unsafe_repository/versions.env" TOOL_RELEASES nvim "$NVIM_VERSION" \
  https://example.invalid/nvim-linux-x86_64.tar.gz "$unsafe_digest"
set +e
unsafe_output=$(HOME="$unsafe_home" "$unsafe_repository/setup-tools" \
  --from "$unsafe_archives" nvim 2>&1)
unsafe_status=$?
set -e
[[ $unsafe_status -ne 0 && $unsafe_output == *'archive link escapes its root'* ]] ||
  fail 'setup-tools accepted an escaping archive symlink'
[[ ! -e $unsafe_home/bin/nvim && ! -L $unsafe_home/bin/nvim ]] ||
  fail 'unsafe archive changed the selected Neovim'

tmux_work=$test_root/tmux-work
tmux_destination=$test_root/tmux-destination
mkdir -p "$tmux_work/tmux-$TMUX_VERSION" "$tmux_destination"
write_fake "$tmux_work/tmux-$TMUX_VERSION/tmux" tmux "$TMUX_VERSION"
tar -C "$tmux_work" -czf "$test_root/tmux.tar.gz" "tmux-$TMUX_VERSION"
TMUX_SHA256=$(sha256sum "$test_root/tmux.tar.gz" | awk '{print $1}')
# shellcheck source=../scripts/setup-lib
source "$repo_dir/scripts/setup-lib"
SETUP_PROGRAM=setup-tools-test
# Used through a nameref in setup_prepare_artifact.
# shellcheck disable=SC2034
declare -A TEST_RELEASES=([tmux]=$'\n'"$TMUX_VERSION|https://example.invalid/tmux.tar.gz|$TMUX_SHA256"$'\n')
setup_prepare_artifact TEST_RELEASES tmux "$TMUX_VERSION" "$test_root/tmux.tar.gz" "$tmux_destination"
[[ -x $tmux_destination/tmux-$TMUX_VERSION/tmux ]] ||
  fail 'shared tree extractor did not preserve an equal source and destination name'

pin_repository=$test_root/pin-repository
pin_archives=$test_root/pin-archives
pin_home=$test_root/pin-home
pin_work=$test_root/pin-work
make_test_repo "$pin_repository"
daily_shellcheck=0.10.0
validation_shellcheck=0.11.0
write_fake "$pin_work/shellcheck-v$daily_shellcheck/shellcheck" shellcheck "$daily_shellcheck"
mkdir -p "$pin_archives/shellcheck/$daily_shellcheck"
tar -C "$pin_work" -cJf \
  "$pin_archives/shellcheck/$daily_shellcheck/shellcheck-v$daily_shellcheck.linux.x86_64.tar.xz" \
  "shellcheck-v$daily_shellcheck"
daily_shellcheck_digest=$(sha256sum \
  "$pin_archives/shellcheck/$daily_shellcheck/shellcheck-v$daily_shellcheck.linux.x86_64.tar.xz")
daily_shellcheck_digest=${daily_shellcheck_digest%% *}
append_release "$pin_repository/versions.env" TOOL_RELEASES shellcheck \
  "$daily_shellcheck" \
  "https://example.invalid/shellcheck-v$daily_shellcheck.linux.x86_64.tar.xz" \
  "$daily_shellcheck_digest"
append_release "$pin_repository/validation.env" VALIDATION_RELEASES shellcheck \
  "$validation_shellcheck" \
  "https://example.invalid/shellcheck-v$validation_shellcheck.linux.x86_64.tar.xz" \
  "$(printf '%064d' 0)"
HOME="$pin_home" "$pin_repository/setup-tools" --from "$pin_archives" shellcheck
assert_link "$pin_home/bin/shellcheck" "shellcheck-$daily_shellcheck"
"$pin_home/bin/shellcheck" --version | grep -F "$daily_shellcheck" >/dev/null

upgrade_repository=$test_root/upgrade-repository
upgrade_archives=$test_root/upgrade-archives
upgrade_home=$test_root/upgrade-home
modified_upgrade_home=$test_root/modified-upgrade-home
upgrade_work=$test_root/upgrade-work
make_test_repo "$upgrade_repository"
make_archives "$upgrade_repository" "$upgrade_archives"
load_test_versions "$upgrade_repository"
upgrade_a_version=$K9S_VERSION
upgrade_a_archive=$upgrade_archives/k9s/$upgrade_a_version/k9s_Linux_amd64.tar.gz
upgrade_a_digest=$(sha256sum "$upgrade_a_archive" | awk '{print $1}')
HOME="$upgrade_home" "$upgrade_repository/setup-tools" --from "$upgrade_archives" k9s
HOME="$modified_upgrade_home" "$upgrade_repository/setup-tools" \
  --from "$upgrade_archives" k9s

upgrade_b_version=0.51.1
write_fake "$upgrade_work/k9s" k9s "$upgrade_b_version"
mkdir -p "$upgrade_archives/k9s/$upgrade_b_version"
tar -C "$upgrade_work" -czf \
  "$upgrade_archives/k9s/$upgrade_b_version/k9s_Linux_amd64.tar.gz" k9s
upgrade_b_digest=$(sha256sum \
  "$upgrade_archives/k9s/$upgrade_b_version/k9s_Linux_amd64.tar.gz" | awk '{print $1}')
append_release "$upgrade_repository/versions.env" TOOL_RELEASES k9s "$upgrade_b_version" \
  https://example.invalid/k9s_Linux_amd64.tar.gz "$upgrade_b_digest"
HOME="$upgrade_home" "$upgrade_repository/setup-tools" --from "$upgrade_archives" k9s
assert_link "$upgrade_home/bin/k9s" "k9s-$upgrade_b_version"
[[ -x $upgrade_home/bin/k9s-$upgrade_a_version ]] ||
  fail 'upgrade removed the retained A installation'

printf '# modified A\n' >>"$modified_upgrade_home/bin/k9s-$upgrade_a_version"
set +e
modified_upgrade_output=$(HOME="$modified_upgrade_home" \
  "$upgrade_repository/setup-tools" --from "$upgrade_archives" k9s 2>&1)
modified_upgrade_status=$?
set -e
[[ $modified_upgrade_status -ne 0 &&
  $modified_upgrade_output == *'refusing foreign link'* ]] ||
  fail 'upgrade accepted a modified selected A installation'
assert_link "$modified_upgrade_home/bin/k9s" "k9s-$upgrade_a_version"

append_release "$upgrade_repository/versions.env" TOOL_RELEASES k9s "$upgrade_a_version" \
  "https://example.invalid/k9s_Linux_amd64.tar.gz" "$upgrade_a_digest"
find "$upgrade_archives" -depth -delete
HOME="$upgrade_home" "$upgrade_repository/setup-tools" --from "$upgrade_archives" k9s
assert_link "$upgrade_home/bin/k9s" "k9s-$upgrade_a_version"

missing_default_repository=$test_root/missing-default-repository
missing_default_archives=$test_root/missing-default-archives
missing_default_home=$test_root/missing-default-home
make_test_repo "$missing_default_repository"
make_archives "$missing_default_repository" "$missing_default_archives"
printf 'TOOL_RELEASES[k9s]=%q\n' \
  $'\n0.51.1|-|-\n0.51.0|https://example.invalid/k9s_Linux_amd64.tar.gz|c3752ad51a5a4015a113819c4eeb6e55a4d0e4b8e652494797532f6fc8161dd7\n' \
  >>"$missing_default_repository/versions.env"
set +e
missing_default_output=$(HOME="$missing_default_home" \
  "$missing_default_repository/setup-tools" --from "$missing_default_archives" k9s 2>&1)
missing_default_status=$?
set -e
[[ $missing_default_status -ne 0 &&
  $missing_default_output == *'offline default k9s 0.51.1 requires an artifact'* ]] ||
  fail 'missing default artifact fell back to a later record'
[[ ! -e $missing_default_home/bin && ! -e $missing_default_home/.local ]] ||
  fail 'missing default artifact changed the target home'

for invalid_list in '' '   '; do
  list_repository=$test_root/list-repository-${#invalid_list}
  list_archives=$test_root/list-archives-${#invalid_list}
  list_home=$test_root/list-home-${#invalid_list}
  make_test_repo "$list_repository"
  make_archives "$list_repository" "$list_archives"
  printf 'TOOL_RELEASES[terraform]=%q\n' "$invalid_list" \
    >>"$list_repository/versions.env"
  set +e
  list_output=$(HOME="$list_home" "$list_repository/setup-tools" \
    --from "$list_archives" k9s 2>&1)
  list_status=$?
  set -e
  [[ $list_status -ne 0 ]] || fail 'empty project version list was accepted'
  [[ $list_output == *'TOOL_RELEASES[terraform]'* ]] ||
    fail 'empty project version list did not report its variable'
  [[ ! -e $list_home/bin && ! -e $list_home/.local ]] ||
    fail 'empty project version list changed the target home'
done

single_repository=$test_root/single-list-repository
single_archives=$test_root/single-list-archives
single_home=$test_root/single-list-home
make_test_repo "$single_repository"
make_archives "$single_repository" "$single_archives"
append_release "$single_repository/versions.env" TOOL_RELEASES terraform \
  1.16.4 https://example.invalid/terraform.zip \
  dc94af0eef1147718ad7c8daea792ed199e3e0492eec180d0adafa2a65a879df
HOME="$single_home" "$single_repository/setup-tools" --from "$single_archives" k9s
assert_link "$single_home/bin/k9s" "k9s-$K9S_VERSION"

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
append_release "$failure_repo/versions.env" TOOL_RELEASES k9s 0.51.1 \
  https://example.invalid/k9s_Linux_amd64.tar.gz \
  0000000000000000000000000000000000000000000000000000000000000000
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
append_release "$pair_repo/versions.env" TOOL_RELEASES uv "$new_uv_version" \
  https://example.invalid/uv-x86_64-unknown-linux-gnu.tar.gz "$new_uv_digest"
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
