#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

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
append_release "$unsafe_repository/tools.env" TOOL_RELEASES nvim "$NVIM_VERSION" \
  "https://example.invalid/nvim/$NVIM_VERSION/nvim-linux-x86_64.tar.gz" "$unsafe_digest"
set +e
unsafe_output=$(run_setup "$unsafe_home" "$unsafe_repository" "$unsafe_archives" nvim 2>&1)
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
# shellcheck source=../../scripts/setup-lib
source "$repo_dir/scripts/setup-lib"
# Used through a nameref in prepare_artifact.
# shellcheck disable=SC2034
declare -A TEST_RELEASES=([tmux]=$'\n'"$TMUX_VERSION|https://example.invalid/tmux.tar.gz|$TMUX_SHA256"$'\n')
prepare_artifact TEST_RELEASES tmux "$TMUX_VERSION" "$test_root/tmux.tar.gz" "$tmux_destination"
[[ -x $tmux_destination/tmux-$TMUX_VERSION/tmux ]] ||
  fail 'shared tree extractor did not preserve an equal source and destination name'

bad_destination=$test_root/bad-checksum-destination
# The shared library reads the catalog through a nameref.
# shellcheck disable=SC2034
TEST_RELEASES[tmux]="$TMUX_VERSION|https://example.invalid/tmux.tar.gz|$(printf '%064d' 0)"
if prepare_artifact TEST_RELEASES tmux "$TMUX_VERSION" \
  "$test_root/tmux.tar.gz" "$bad_destination" >"$test_root/bad-checksum.log" 2>&1; then
  fail 'shared artifact preparation accepted an invalid checksum'
fi
[[ ! -e $bad_destination ]] || fail 'invalid checksum produced an extracted payload'

bad_destination=$test_root/bad-archive-destination
mkdir -p "$bad_destination"
artifact_layout nvim "$NVIM_VERSION" nvim-linux-x86_64.tar.gz
if extract_artifact \
  "$unsafe_archives/nvim/$NVIM_VERSION/nvim-linux-x86_64.tar.gz" \
  "$bad_destination" >"$test_root/bad-archive.log" 2>&1; then
  fail 'shared extractor accepted an escaping archive link'
fi
[[ -z $(find "$bad_destination" -mindepth 1 -print -quit) ]] ||
  fail 'unsafe archive produced an extracted payload'

set +e
missing_output=$(run_setup "$test_root/missing-home" "$test_repository" \
  "$test_root/missing archive" k9s 2>&1)
missing_status=$?
set -e
[[ $missing_status -eq 22 &&
  $missing_output == *"download failed: https://example.invalid/k9s/$K9S_VERSION/k9s_Linux_amd64.tar.gz"* ]] ||
  fail 'setup-tools hid the failed download'
[[ ! -e $test_root/missing-home/bin/k9s && ! -L $test_root/missing-home/bin/k9s &&
  ! -e $test_root/missing-home/bin/k9s-$K9S_VERSION ]] ||
  fail 'failed download installed or selected a tool'

failure_repo="$test_root/failure-repository"
failure_archives="$test_root/failure-archives"
failure_home="$test_root/failure-home"
make_test_repo "$failure_repo"
make_archives "$failure_repo" "$failure_archives"
run_setup "$failure_home" "$failure_repo" "$failure_archives" k9s
old_target=$(readlink -- "$failure_home/bin/k9s")
write_fake "$failure_archives/k9s/99.1.0/k9s_Linux_amd64.tar.gz" k9s 99.1.0
append_release "$failure_repo/tools.env" TOOL_RELEASES k9s 99.1.0 \
  https://example.invalid/k9s/99.1.0/k9s_Linux_amd64.tar.gz \
  0000000000000000000000000000000000000000000000000000000000000000
set +e
run_setup "$failure_home" "$failure_repo" "$failure_archives" k9s >/dev/null 2>&1
checksum_status=$?
set -e
[[ $checksum_status -ne 0 ]] || fail 'bad checksum was accepted'
[[ $(readlink -- "$failure_home/bin/k9s") == "$old_target" ]] ||
  fail 'checksum failure changed the selected version'
[[ ! -e $failure_home/bin/k9s-99.1.0 ]] || fail 'checksum failure installed a candidate'

printf 'setup_tools: archives passed\n'
