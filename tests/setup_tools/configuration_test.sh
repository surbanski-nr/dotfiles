#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

prerequisite_repository=$test_root/prerequisite-repository
prerequisite_home=$test_root/prerequisite-home
make_test_repo "$prerequisite_repository"
printf "SETUP_PREREQUISITES[setup-tools]+=' dotfiles-fixture-missing-command'\n" \
  >>"$prerequisite_repository/system.env"
set +e
prerequisite_output=$(run_setup "$prerequisite_home" "$prerequisite_repository" \
  "$archive_root" k9s 2>&1)
prerequisite_status=$?
set -e
[[ $prerequisite_status -ne 0 && $prerequisite_output == \
  *'setup-tools: required command is missing: dotfiles-fixture-missing-command'* ]] ||
  fail 'setup-tools ignored its configured prerequisites'
[[ ! -e $prerequisite_home/bin && ! -e $prerequisite_home/.local ]] ||
  fail 'a missing prerequisite changed the target home'

set +e
retired_from_output=$(run_setup "$test_root/retired-from-home" "$test_repository" \
  "$archive_root" --from "$archive_root" k9s 2>&1)
retired_from_status=$?
set -e
[[ $retired_from_status -ne 0 && $retired_from_output == *'unknown option: --from'* ]] ||
  fail 'setup-tools accepted the retired --from option'
[[ ! -e $test_root/retired-from-home/bin && ! -e $test_root/retired-from-home/.local ]] ||
  fail 'retired --from option changed the target home'

unsupported_repository=$test_root/unsupported-repository
unsupported_home=$test_root/unsupported-home
make_test_repo "$unsupported_repository"
printf 'TOOLS+=(fzf)\n' >>"$unsupported_repository/tools.env"
if run_setup "$unsupported_home" "$unsupported_repository" "$archive_root" \
  k9s >"$test_root/unsupported-profile.log" 2>&1; then
  fail 'setup-tools accepted a profile tool without a command adapter'
fi
[[ ! -e $unsupported_home/bin && ! -e $unsupported_home/.local ]] ||
  fail 'invalid profile changed the target home'

pin_repository=$test_root/pin-repository
pin_archives=$test_root/pin-archives
pin_home=$test_root/pin-home
pin_work=$test_root/pin-work
make_test_repo "$pin_repository"
daily_shellcheck=9.0.0
write_fake "$pin_work/shellcheck-v$daily_shellcheck/shellcheck" shellcheck "$daily_shellcheck"
mkdir -p "$pin_archives/shellcheck/$daily_shellcheck"
tar -C "$pin_work" -cJf \
  "$pin_archives/shellcheck/$daily_shellcheck/shellcheck-v$daily_shellcheck.linux.x86_64.tar.xz" \
  "shellcheck-v$daily_shellcheck"
daily_shellcheck_digest=$(sha256sum \
  "$pin_archives/shellcheck/$daily_shellcheck/shellcheck-v$daily_shellcheck.linux.x86_64.tar.xz")
daily_shellcheck_digest=${daily_shellcheck_digest%% *}
append_release "$pin_repository/tools.env" TOOL_RELEASES shellcheck \
  "$daily_shellcheck" \
  "https://example.invalid/shellcheck/$daily_shellcheck/shellcheck-v$daily_shellcheck.linux.x86_64.tar.xz" \
  "$daily_shellcheck_digest"
run_setup "$pin_home" "$pin_repository" "$pin_archives" shellcheck
assert_link "$pin_home/bin/shellcheck" "shellcheck-$daily_shellcheck"
"$pin_home/bin/shellcheck" --version | grep -F "$daily_shellcheck" >/dev/null

missing_default_repository=$test_root/missing-default-repository
missing_default_archives=$test_root/missing-default-archives
missing_default_home=$test_root/missing-default-home
make_test_repo "$missing_default_repository"
make_archives "$missing_default_repository" "$missing_default_archives"
printf 'TOOL_RELEASES[k9s]=%q\n' \
  $'\n99.1.0|-|-\n99.0.0|https://example.invalid/k9s_Linux_amd64.tar.gz|1111111111111111111111111111111111111111111111111111111111111111\n' \
  >>"$missing_default_repository/tools.env"
set +e
missing_default_output=$(run_setup "$missing_default_home" \
  "$missing_default_repository" "$missing_default_archives" k9s 2>&1)
missing_default_status=$?
set -e
[[ $missing_default_status -ne 0 &&
  $missing_default_output == *'offline default k9s 99.1.0 requires an artifact'* ]] ||
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
    >>"$list_repository/tools.env"
  set +e
  list_output=$(run_setup "$list_home" "$list_repository" "$list_archives" k9s 2>&1)
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
append_release "$single_repository/tools.env" TOOL_RELEASES terraform \
  9.0.0 https://example.invalid/terraform.zip \
  0000000000000000000000000000000000000000000000000000000000000000
run_setup "$single_home" "$single_repository" "$single_archives" k9s
assert_link "$single_home/bin/k9s" "k9s-$K9S_VERSION"

printf 'setup_tools: configuration passed\n'
