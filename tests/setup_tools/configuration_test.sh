#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

for profile in TOOLS OFFLINE_RELEASE_TOOLS; do
  empty_repository=$test_root/empty-$profile-repository
  empty_home=$test_root/empty-$profile-home
  make_test_repo "$empty_repository"
  printf '%s=()\n' "$profile" >>"$empty_repository/tools.env"
  if empty_output=$(run_setup "$empty_home" "$empty_repository" "$archive_root" 2>&1); then
    fail "setup-tools accepted empty $profile"
  fi
  [[ $empty_output == *"$profile is empty"* ]] ||
    fail "empty $profile did not report the invalid list"
  [[ ! -e $empty_home ]] || fail "empty $profile changed the target home"
done

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
[[ $prerequisite_status -ne 0 && $prerequisite_output == *'setup-tools: required command is missing: dotfiles-fixture-missing-command'* ]] ||
  fail 'setup-tools ignored its configured prerequisites'
[[ ! -e $prerequisite_home/dotfiles-releases/online/bin && ! -e $prerequisite_home/.local ]] ||
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
printf 'TOOLS+=(helm-schema)\n' >>"$unsupported_repository/tools.env"
if run_setup "$unsupported_home" "$unsupported_repository" "$archive_root" \
  k9s >"$test_root/unsupported-profile.log" 2>&1; then
  fail 'setup-tools accepted a profile tool without a command adapter'
fi
[[ ! -e $unsupported_home/dotfiles-releases/online/bin && ! -e $unsupported_home/.local ]] ||
  fail 'invalid profile changed the target home'

kubens_repository=$test_root/kubens-repository
kubens_home=$test_root/kubens-home
make_test_repo "$kubens_repository"
append_release "$kubens_repository/tools.env" TOOL_RELEASES kubens \
  99.0.0 https://example.invalid/kubens_v99.0.0_linux_x86_64.tar.gz \
  0000000000000000000000000000000000000000000000000000000000000000
if kubens_output=$(run_setup "$kubens_home" "$kubens_repository" "$archive_root" k9s 2>&1); then
  fail 'setup-tools accepted mismatched kubectx and kubens defaults'
fi
[[ $kubens_output == *'kubectx and kubens defaults must use the same version'* ]] ||
  fail 'mismatched kubectx and kubens defaults were not reported'
[[ ! -e $kubens_home/dotfiles-releases/online/bin && ! -e $kubens_home/.local ]] ||
  fail 'mismatched kubectx and kubens defaults changed the target home'

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
assert_link "$pin_home/dotfiles-releases/online/bin/shellcheck" "../tools/bin/shellcheck-$daily_shellcheck"
"$pin_home/dotfiles-releases/online/bin/shellcheck" --version | grep -F "$daily_shellcheck" >/dev/null

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
  $missing_default_output == *'TOOLS release k9s 99.1.0 requires an artifact'* ]] ||
  fail 'missing default artifact fell back to a later record'
[[ ! -e $missing_default_home/dotfiles-releases/online/bin && ! -e $missing_default_home/.local ]] ||
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
  [[ ! -e $list_home/dotfiles-releases/online/bin && ! -e $list_home/.local ]] ||
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
assert_link "$single_home/dotfiles-releases/online/bin/k9s" "../tools/bin/k9s-$K9S_VERSION"

invalid_plugin_index=0
for invalid_plugin in \
  'http://example.invalid/plugin.git|0000000000000000000000000000000000000000' \
  'https://example.invalid/plugin.git|not-a-commit' \
  'https://example.invalid/plugin.git|0000000000000000000000000000000000000000|extra' \
  'https://example.invalid/plugin.git|'; do
  invalid_plugin_index=$((invalid_plugin_index + 1))
  invalid_plugin_repository=$test_root/invalid-plugin-$invalid_plugin_index
  invalid_plugin_home=$test_root/invalid-plugin-home-$invalid_plugin_index
  make_test_repo "$invalid_plugin_repository"
  printf 'TMUX_PLUGINS[tmux-sensible]=%q\n' "$invalid_plugin" \
    >>"$invalid_plugin_repository/tools.env"
  if invalid_plugin_output=$(run_setup "$invalid_plugin_home" \
    "$invalid_plugin_repository" "$archive_root" k9s 2>&1); then
    fail 'setup-tools accepted an invalid Git plugin record'
  fi
  [[ $invalid_plugin_output == *'TMUX_PLUGINS[tmux-sensible]'* ]] ||
    fail 'invalid plugin error did not identify its catalog record'
  [[ ! -e $invalid_plugin_home/dotfiles-releases/online/bin && ! -e $invalid_plugin_home/.local &&
    ! -e $invalid_plugin_home/.tmux ]] ||
    fail 'an invalid Git plugin record changed HOME'
done

printf 'setup_tools: configuration passed\n'
