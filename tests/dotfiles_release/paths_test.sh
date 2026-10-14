#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

reserved_root=$test_root/reserved-paths
mkdir -p "$reserved_root"

test_home=$reserved_root/lock-home
private_lock_target=$reserved_root/private-lock-target
mkdir -p "$test_home/dotfiles-releases/.state"
printf 'private lock target\n' >"$private_lock_target"
chmod 0640 "$private_lock_target"
private_lock_digest=$(sha256sum "$private_lock_target")
private_lock_mode=$(stat -c %a "$private_lock_target")
ln -s "$private_lock_target" "$test_home/dotfiles-releases/.state/lock"
set +e
reserved_output=$(run_manager list 2>&1)
reserved_status=$?
set -e
[[ $reserved_status -ne 0 && $reserved_output == *'invalid reserved state path'* ]] ||
  fail 'foreign lock symlink was accepted'
[[ $(sha256sum "$private_lock_target") == "$private_lock_digest" &&
  $(stat -c %a "$private_lock_target") == "$private_lock_mode" ]] ||
  fail 'foreign lock symlink target was modified'
assert_link "$test_home/dotfiles-releases/.state/lock" "$private_lock_target"

test_home=$reserved_root/broken-lock-home
mkdir -p "$test_home/dotfiles-releases/.state"
ln -s "$reserved_root/missing-lock-target" "$test_home/dotfiles-releases/.state/lock"
set +e
run_manager list >/dev/null 2>&1
reserved_status=$?
set -e
[[ $reserved_status -ne 0 ]] || fail 'broken lock symlink was accepted'
assert_link "$test_home/dotfiles-releases/.state/lock" "$reserved_root/missing-lock-target"

for selection in current previous; do
  test_home=$reserved_root/regular-$selection-home
  mkdir -p "$test_home/dotfiles-releases"
  printf 'private selection\n' >"$test_home/dotfiles-releases/$selection"
  selection_digest=$(sha256sum "$test_home/dotfiles-releases/$selection")
  set +e
  run_manager list >/dev/null 2>&1
  reserved_status=$?
  set -e
  [[ $reserved_status -ne 0 ]] || fail "regular $selection was accepted"
  [[ $(sha256sum "$test_home/dotfiles-releases/$selection") == "$selection_digest" ]] ||
    fail "regular $selection was modified"
  [[ ! -e $test_home/dotfiles-releases/.state ]] ||
    fail "regular $selection was rejected only after a state write"
done

test_home=$reserved_root/broken-selection-home
mkdir -p "$test_home/dotfiles-releases"
ln -s dotfiles-aaaaaaaaaaaa "$test_home/dotfiles-releases/current"
set +e
run_manager list >/dev/null 2>&1
reserved_status=$?
set -e
[[ $reserved_status -ne 0 ]] || fail 'broken current selection was accepted'
assert_link "$test_home/dotfiles-releases/current" dotfiles-aaaaaaaaaaaa
[[ ! -e $test_home/dotfiles-releases/.state ]] ||
  fail 'broken current selection was rejected only after a state write'

test_home=$reserved_root/release-root-home
outside_release_root=$reserved_root/outside-release-root
mkdir -p "$test_home" "$outside_release_root"
printf 'outside marker\n' >"$outside_release_root/marker"
outside_release_digest=$(sha256sum "$outside_release_root/marker")
ln -s "$outside_release_root" "$test_home/dotfiles-releases"
set +e
run_manager list >/dev/null 2>&1
reserved_status=$?
set -e
[[ $reserved_status -ne 0 ]] || fail 'symlink release root was accepted'
[[ $(sha256sum "$outside_release_root/marker") == "$outside_release_digest" ]] ||
  fail 'symlink release root target was modified'

test_home=$reserved_root/state-home
outside_state=$reserved_root/outside-state
mkdir -p "$test_home/dotfiles-releases" "$outside_state"
printf 'outside state marker\n' >"$outside_state/marker"
outside_state_digest=$(sha256sum "$outside_state/marker")
ln -s "$outside_state" "$test_home/dotfiles-releases/.state"
set +e
run_manager list >/dev/null 2>&1
reserved_status=$?
set -e
[[ $reserved_status -ne 0 ]] || fail 'symlink state directory was accepted'
[[ $(sha256sum "$outside_state/marker") == "$outside_state_digest" ]] ||
  fail 'symlink state target was modified'

test_home=$reserved_root/ownership-home
mkdir -p "$test_home/dotfiles-releases/.state/ownership.tsv"
set +e
run_manager list >/dev/null 2>&1
reserved_status=$?
set -e
[[ $reserved_status -ne 0 && -d $test_home/dotfiles-releases/.state/ownership.tsv ]] ||
  fail 'directory ownership record was accepted or replaced'

test_home=$reserved_root/parent-link-home
outside_bin=$reserved_root/outside-bin
mkdir -p "$test_home" "$outside_bin"
printf 'outside bin marker\n' >"$outside_bin/marker"
outside_bin_digest=$(sha256sum "$outside_bin/marker")
ln -s "$outside_bin" "$test_home/bin"
set +e
parent_output=$(run_manager install "$artifact_one" 2>&1)
parent_status=$?
set -e
[[ $parent_status -ne 0 && $parent_output == *'symlink parent'* ]] ||
  fail 'managed path with a symlink parent was accepted'
[[ $(sha256sum "$outside_bin/marker") == "$outside_bin_digest" ]] ||
  fail 'managed symlink parent target was modified'
[[ ! -e $test_home/dotfiles-releases/current &&
  ! -e $test_home/dotfiles-releases/.state/pending.env &&
  ! -e $test_home/dotfiles-releases/$id_one ]] ||
  fail 'parent-link conflict retained partial release state'

foreign_plugin_home=$test_root/foreign-plugin-home
foreign_plugin=$foreign_plugin_home/.tmux/plugins/tmux-sensible
mkdir -p "$(dirname -- "$foreign_plugin")"
cp -a "$test_root/stage-one/$id_one/share/tmux/plugins/tmux-sensible" "$foreign_plugin"
git -C "$foreign_plugin" remote set-url origin https://example.invalid/foreign.git
test_home=$foreign_plugin_home
if run_manager install "$artifact_one" >"$test_root/foreign-plugin.log" 2>&1; then
  fail 'foreign tmux plugin checkout was adopted'
fi
[[ ! -L $foreign_plugin &&
  $(git -C "$foreign_plugin" remote get-url origin) == https://example.invalid/foreign.git &&
  ! -e $test_home/dotfiles-releases/current ]] ||
  fail 'foreign tmux plugin checkout changed after rejected install'

foreign_home="$test_root/foreign home"
mkdir -p "$foreign_home/bin"
ln -s /usr/bin/true "$foreign_home/bin/rg"
test_home=$foreign_home
set +e
foreign_output=$(run_manager install "$artifact_one" 2>&1)
foreign_status=$?
set -e
[[ $foreign_status -ne 0 && $foreign_output == *'foreign managed path exists'* ]] ||
  fail 'foreign managed link was accepted'
assert_link "$foreign_home/bin/rg" /usr/bin/true

printf 'dotfiles_release: paths passed\n'
