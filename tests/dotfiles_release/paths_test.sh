#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

test_home=$test_root/empty-home
mkdir -p "$test_home"
run_manager list >"$test_root/empty-list.log"
[[ ! -e $test_home/dotfiles-releases && $(wc -l <"$test_root/empty-list.log") == 1 ]] ||
  fail 'listing an empty store created files'

test_home=$test_root/regular-current-home
mkdir -p "$test_home/dotfiles-releases"
printf 'private selection\n' >"$test_home/dotfiles-releases/current"
selection_digest=$(sha256sum "$test_home/dotfiles-releases/current")
if run_manager install "$artifact_one" >/dev/null 2>&1; then fail 'regular current was overwritten'; fi
[[ $(sha256sum "$test_home/dotfiles-releases/current") == "$selection_digest" ]] ||
  fail 'invalid current data was modified'

test_home=$test_root/release-root-home
outside_root=$test_root/outside-root
mkdir -p "$test_home" "$outside_root"
printf 'outside marker\n' >"$outside_root/marker"
ln -s "$outside_root" "$test_home/dotfiles-releases"
if run_manager install "$artifact_one" >/dev/null 2>&1; then fail 'symlink release root was accepted'; fi
[[ $(<"$outside_root/marker") == 'outside marker' &&
  $(find "$outside_root" -mindepth 1 -maxdepth 1 | wc -l) == 1 ]] ||
  fail 'symlink root modified outside data'

test_home=$test_root/parent-link-home
outside_config=$test_root/outside-config
mkdir -p "$test_home" "$outside_config"
printf 'outside config marker\n' >"$outside_config/marker"
ln -s "$outside_config" "$test_home/.config"
if run_manager install "$artifact_one" >"$test_root/parent-link.log" 2>&1; then
  fail 'symlink parent was accepted'
fi
[[ $(<"$test_root/parent-link.log") == *'symlink parent'* &&
  $(<"$outside_config/marker") == 'outside config marker' &&
  ! -e $test_home/dotfiles-releases/$id_one ]] ||
  fail 'symlink parent rejection changed outside data or retained a candidate'

test_home=$test_root/user-bin-link-home
outside_bin=$test_root/outside-bin
mkdir -p "$test_home" "$outside_bin"
printf 'outside bin marker\n' >"$outside_bin/marker"
ln -s "$outside_bin" "$test_home/bin"
run_manager install "$artifact_one" >/dev/null
run_manager health >/dev/null
run_manager uninstall >/dev/null
assert_link "$test_home/bin" "$outside_bin"
[[ $(<"$outside_bin/marker") == 'outside bin marker' &&
  $(find "$outside_bin" -mindepth 1 -maxdepth 1 | wc -l) == 1 ]] ||
  fail 'release lifecycle changed the user-owned bin directory'

test_home=$test_root/saved-conflict-home
mkdir -p "$test_home"
printf 'current private file\n' >"$test_home/.bashrc"
printf 'older saved original\n' >"$test_home/.bashrc.before-dotfiles-release"
if run_manager install "$artifact_one" >"$test_root/saved-conflict.log" 2>&1; then
  fail 'existing backup was overwritten'
fi
[[ $(<"$test_home/.bashrc") == 'current private file' &&
  $(<"$test_home/.bashrc.before-dotfiles-release") == 'older saved original' &&
  ! -e $test_home/dotfiles-releases/$id_one ]] ||
  fail 'backup conflict modified user data'

test_home=$test_root/foreign-link-home
mkdir -p "$test_home/bin"
ln -s /usr/bin/true "$test_home/bin/rg"
run_manager install "$artifact_one" >/dev/null
assert_link "$test_home/bin/rg" /usr/bin/true
[[ ! -e $test_home/bin/rg.before-dotfiles-release ]] || fail 'release backed up a user executable'
run_manager uninstall >/dev/null
assert_link "$test_home/bin/rg" /usr/bin/true

test_home=$test_root/custom-store-home
custom_root="$test_home/releases with spaces"
mkdir -p "$test_home"
DOTFILES_RELEASE_ROOT="$custom_root" run_manager install "$artifact_one" >/dev/null
[[ -x $custom_root/current/bin/rg && ! -e $test_home/bin ]] ||
  fail 'custom release did not expose commands directly or touched user bin'
DOTFILES_RELEASE_ROOT="$custom_root" run_manager uninstall >/dev/null
[[ ! -e $test_home/bin && ! -e $custom_root/$id_one ]] ||
  fail 'custom release root was not respected on uninstall'

for unsafe_root in / "$test_home" "$test_home/../elsewhere"; do
  if DOTFILES_RELEASE_ROOT="$unsafe_root" run_manager uninstall "$id_one" >/dev/null 2>&1; then
    fail 'unsafe release root was accepted'
  fi
done
for unsafe_id in ../../outside dotfiles-xyz; do
  if run_manager uninstall "$unsafe_id" >/dev/null 2>&1 ||
    run_manager set "$unsafe_id" >/dev/null 2>&1; then
    fail 'unsafe release ID was accepted'
  fi
done

test_home=$test_root/modified-path-home
mkdir -p "$test_home"
run_manager install "$artifact_one" >/dev/null
unlink "$test_home/.gitconfig"
printf 'user replacement\n' >"$test_home/.gitconfig"
run_manager uninstall >/dev/null
[[ $(<"$test_home/.gitconfig") == 'user replacement' ]] ||
  fail 'uninstall replaced a user modification'

test_home=$test_root/missing-path-with-backup-home
mkdir -p "$test_home"
printf 'saved before interruption\n' >"$test_home/.bashrc.before-dotfiles-release"
run_manager install "$artifact_one" >/dev/null
[[ $(<"$test_home/.bashrc.before-dotfiles-release") == 'saved before interruption' ]] ||
  fail 'activation modified an original already saved beside an absent path'
run_manager uninstall >/dev/null
[[ $(<"$test_home/.bashrc") == 'saved before interruption' ]] ||
  fail 'uninstall did not restore the previously saved original'

printf 'dotfiles_release: paths passed\n'
