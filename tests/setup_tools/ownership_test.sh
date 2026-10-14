#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

foreign_home=$test_root/foreign-home
mkdir -p "$foreign_home/bin"
write_fake "$foreign_home/bin/k9s-manual" k9s manual
ln -s k9s-manual "$foreign_home/bin/k9s"
foreign_hash=$(sha256sum "$foreign_home/bin/k9s-manual")
set +e
foreign_output=$(run_setup "$foreign_home" "$test_repository" "$archive_root" k9s 2>&1)
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
foreign_nvim_output=$(run_setup "$foreign_nvim_home" "$test_repository" "$archive_root" nvim 2>&1)
foreign_nvim_status=$?
set -e
[[ $foreign_nvim_status -ne 0 ]] || fail 'foreign nvim-v* link was accepted'
[[ $foreign_nvim_output == *'refusing foreign link'* ]] ||
  fail 'foreign nvim-v* link conflict was not reported'
assert_link "$foreign_nvim_home/bin/nvim" nvim-v999/bin/nvim
[[ $(sha256sum "$foreign_nvim_home/bin/nvim-v999/bin/nvim") == "$foreign_nvim_hash" ]] ||
  fail 'foreign nvim-v* target was changed'

foreign_go_home=$test_root/foreign-go-home
mkdir -p "$foreign_go_home/bin"
write_fake "$foreign_go_home/bin/gofmt" gofmt manual
foreign_go_hash=$(sha256sum "$foreign_go_home/bin/gofmt")
if run_setup "$foreign_go_home" "$test_repository" "$archive_root" go \
  >"$test_root/foreign-go.log" 2>&1; then
  fail 'Go SDK install overwrote a foreign gofmt'
fi
[[ ! -e $foreign_go_home/bin/go && $(sha256sum "$foreign_go_home/bin/gofmt") == "$foreign_go_hash" ]] ||
  fail 'Go SDK pair conflict changed the prior selection'

run_setup "$test_home" "$test_repository" "$archive_root" go >/dev/null

go_upgrade_repository=$test_root/go-upgrade-repository
go_upgrade_archives=$test_root/go-upgrade-archives
go_baseline_version=$GO_VERSION
go_candidate_version=99.1.0
make_test_repo "$go_upgrade_repository"
append_release "$go_upgrade_repository/tools.env" TOOL_RELEASES go "$go_candidate_version" \
  https://example.invalid/placeholder "$(printf '%064d' 0)"
make_archives "$go_upgrade_repository" "$go_upgrade_archives"
run_setup "$test_home" "$go_upgrade_repository" "$go_upgrade_archives" go
assert_link "$test_home/bin/go" "go-$go_candidate_version/bin/go"
assert_link "$test_home/bin/gofmt" "go-$go_candidate_version/bin/gofmt"
[[ -x $test_home/bin/go-$go_baseline_version/bin/go ]] || fail 'Go SDK upgrade removed the prior tree'
run_setup "$test_home" "$test_repository" "$archive_root" go
assert_link "$test_home/bin/go" "go-$go_baseline_version/bin/go"
assert_link "$test_home/bin/gofmt" "go-$go_baseline_version/bin/gofmt"
[[ -x $test_home/bin/go-$go_candidate_version/bin/go ]] || fail 'Go SDK rollback removed the other tree'
load_test_versions "$test_repository"

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
run_setup "$upgrade_home" "$upgrade_repository" "$upgrade_archives" k9s
run_setup "$modified_upgrade_home" "$upgrade_repository" "$upgrade_archives" k9s

upgrade_b_version=99.1.0
write_fake "$upgrade_work/k9s" k9s "$upgrade_b_version"
mkdir -p "$upgrade_archives/k9s/$upgrade_b_version"
tar -C "$upgrade_work" -czf \
  "$upgrade_archives/k9s/$upgrade_b_version/k9s_Linux_amd64.tar.gz" k9s
upgrade_b_digest=$(sha256sum \
  "$upgrade_archives/k9s/$upgrade_b_version/k9s_Linux_amd64.tar.gz" | awk '{print $1}')
append_release "$upgrade_repository/tools.env" TOOL_RELEASES k9s "$upgrade_b_version" \
  "https://example.invalid/k9s/$upgrade_b_version/k9s_Linux_amd64.tar.gz" "$upgrade_b_digest"
run_setup "$upgrade_home" "$upgrade_repository" "$upgrade_archives" k9s
assert_link "$upgrade_home/bin/k9s" "k9s-$upgrade_b_version"
[[ -x $upgrade_home/bin/k9s-$upgrade_a_version ]] ||
  fail 'upgrade removed the retained A installation'

printf '# modified A\n' >>"$modified_upgrade_home/bin/k9s-$upgrade_a_version"
set +e
modified_upgrade_output=$(run_setup "$modified_upgrade_home" \
  "$upgrade_repository" "$upgrade_archives" k9s 2>&1)
modified_upgrade_status=$?
set -e
[[ $modified_upgrade_status -ne 0 &&
  $modified_upgrade_output == *'refusing foreign link'* ]] ||
  fail 'upgrade accepted a modified selected A installation'
assert_link "$modified_upgrade_home/bin/k9s" "k9s-$upgrade_a_version"

append_release "$upgrade_repository/tools.env" TOOL_RELEASES k9s "$upgrade_a_version" \
  "https://example.invalid/k9s/$upgrade_a_version/k9s_Linux_amd64.tar.gz" "$upgrade_a_digest"
find "$upgrade_archives" -depth -delete
run_setup "$upgrade_home" "$upgrade_repository" "$upgrade_archives" k9s
assert_link "$upgrade_home/bin/k9s" "k9s-$upgrade_a_version"
# Invalid state must not be treated as a fresh installation, even with no payload.
corrupt_home=$test_root/corrupt-state-home
mkdir -p "$corrupt_home/.local/state/dotfiles/setup-tools"
printf 'not a state record\n' >"$corrupt_home/.local/state/dotfiles/setup-tools/k9s-$K9S_VERSION.state"
if run_setup "$corrupt_home" "$test_repository" "$archive_root" k9s \
  >"$test_root/corrupt-state.log" 2>&1; then
  fail 'malformed ownership state was overwritten'
fi
grep -F 'invalid installation state' "$test_root/corrupt-state.log" >/dev/null ||
  fail 'malformed ownership state was not reported'
[[ ! -e $corrupt_home/bin/k9s-$K9S_VERSION ]] || fail 'malformed state installed a payload'

printf 'setup_tools: ownership passed\n'
