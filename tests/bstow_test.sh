#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
bstow=$repo_dir/bstow
test_root=$(mktemp -d)
stow_dir=$test_root/home/repo
target_dir=$test_root/home

cleanup() {
    find "$test_root" -depth -delete
}
trap cleanup EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_contains() {
    local value=$1
    local expected=$2
    [[ $value == *"$expected"* ]] || fail "expected output to contain: $expected"
}

assert_link_target() {
    local link=$1
    local expected=$2
    [[ -L $link ]] || fail "expected symlink: $link"
    [[ $(readlink "$link") == "$expected" ]] || fail "unexpected target for $link"
}

run_bstow() {
    local output
    local status
    if output=$(BSTOW_STATE_DIR="$test_root/state" timeout 10s "$bstow" "$@" 2>&1); then
        status=0
    else
        status=$?
    fi
    BSTOW_OUTPUT=$output
    BSTOW_STATUS=$status
}

reset_target() {
    local path=$1
    if [[ -L $path || -f $path ]]; then
        unlink "$path"
    fi
}

mkdir -p "$stow_dir/bash"
touch "$stow_dir/bash/.bashrc"

target=$target_dir/.bashrc
relative_source=repo/bash/.bashrc
absolute_source=$stow_dir/bash/.bashrc

ln -s "$relative_source" "$target"
run_bstow -d "$stow_dir" -t "$target_dir" stow bash
[[ $BSTOW_STATUS -eq 0 ]] || fail 'equivalent relative link was rejected'
assert_link_target "$target" "$relative_source"
[[ $BSTOW_OUTPUT != *'points elsewhere'* ]] || fail 'equivalent relative link was reported as foreign'

run_bstow -n -d "$stow_dir" -t "$target_dir" restow bash
[[ $BSTOW_STATUS -eq 0 ]] || fail 'short dry-run failed for an equivalent relative link'
assert_contains "$BSTOW_OUTPUT" '[DRY-RUN] Preview only'
assert_contains "$BSTOW_OUTPUT" 'Would relink'
assert_link_target "$target" "$relative_source"

run_bstow --dry-run --dir "$stow_dir" --target "$target_dir" restow bash
[[ $BSTOW_STATUS -eq 0 ]] || fail 'long dry-run option failed'
assert_contains "$BSTOW_OUTPUT" '[DRY-RUN] Preview only'
assert_contains "$BSTOW_OUTPUT" 'Would relink'
assert_link_target "$target" "$relative_source"

reset_target "$target"
touch "$target"
run_bstow --dry-run --dir "$stow_dir" --target "$target_dir" stow bash
[[ $BSTOW_STATUS -ne 0 ]] || fail 'dry-run accepted a conflicting regular file'
assert_contains "$BSTOW_OUTPUT" 'File exists and is not a symlink'
[[ -f $target && ! -L $target ]] || fail 'dry-run changed a conflicting regular file'

reset_target "$target"
touch "$target_dir/other"
ln -s other "$target"
run_bstow --dry-run --dir "$stow_dir" --target "$target_dir" stow bash
[[ $BSTOW_STATUS -ne 0 ]] || fail 'dry-run accepted a foreign symlink without force'
assert_contains "$BSTOW_OUTPUT" 'Symlink exists and points elsewhere'
assert_link_target "$target" other

run_bstow --dir "$stow_dir" --target "$target_dir" stow bash
[[ $BSTOW_STATUS -ne 0 ]] || fail 'stow replaced a foreign symlink without force'
assert_link_target "$target" other

run_bstow --dry-run --force --dir "$stow_dir" --target "$target_dir" stow bash
[[ $BSTOW_STATUS -eq 0 ]] || fail 'forced dry-run rejected a foreign symlink'
assert_contains "$BSTOW_OUTPUT" 'Would replace symlink'
assert_link_target "$target" other

run_bstow --force --dir "$stow_dir" --target "$target_dir" stow bash
[[ $BSTOW_STATUS -eq 0 ]] || fail 'forced stow did not replace a foreign symlink'
assert_link_target "$target" "$absolute_source"

reset_target "$target"
run_bstow --dry-run --dir "$stow_dir" --target "$target_dir" stow bash
[[ $BSTOW_STATUS -eq 0 ]] || fail 'dry-run rejected an absent destination'
assert_contains "$BSTOW_OUTPUT" 'Would link'
[[ ! -e $target && ! -L $target ]] || fail 'dry-run created an absent destination'

mkdir -p "$stow_dir/mixed"
touch "$stow_dir/mixed/.managed" "$stow_dir/mixed/.conflict"
ln -s "$stow_dir/mixed/.managed" "$target_dir/.managed"
touch "$target_dir/.conflict"
run_bstow --dir "$stow_dir" --target "$target_dir" restow mixed
[[ $BSTOW_STATUS -ne 0 ]] || fail 'restow accepted a package containing a conflict'
assert_link_target "$target_dir/.managed" "$stow_dir/mixed/.managed"
[[ -f $target_dir/.conflict && ! -L $target_dir/.conflict ]] || fail 'restow changed a conflicting file'

mkdir -p "$stow_dir/prune/.config/prune"
touch "$stow_dir/prune/.config/prune/current" "$stow_dir/prune/.config/prune/obsolete"
run_bstow --dir "$stow_dir" --target "$target_dir" stow prune
[[ $BSTOW_STATUS -eq 0 ]] || fail 'initial prune package stow failed'
obsolete_link=$target_dir/.config/prune/obsolete
assert_link_target "$obsolete_link" "$stow_dir/prune/.config/prune/obsolete"

# Simulate links created by a bstow version that predates ownership state.
rm -rf "$test_root/state"
rm "$stow_dir/prune/.config/prune/obsolete"
run_bstow --dry-run --dir "$stow_dir" --target "$target_dir" restow prune
[[ $BSTOW_STATUS -eq 0 ]] || fail 'dry-run rejected a package with an obsolete managed link'
assert_contains "$BSTOW_OUTPUT" "Would remove: $obsolete_link"
[[ -L $obsolete_link ]] || fail 'dry-run removed an obsolete managed link'

run_bstow --dir "$stow_dir" --target "$target_dir" restow prune
[[ $BSTOW_STATUS -eq 0 ]] || fail 'restow failed to prune an obsolete managed link'
[[ ! -e $obsolete_link && ! -L $obsolete_link ]] || fail 'restow retained an obsolete managed link'
assert_link_target "$target_dir/.config/prune/current" "$stow_dir/prune/.config/prune/current"

touch "$stow_dir/prune/.config/prune/replaced"
run_bstow --dir "$stow_dir" --target "$target_dir" restow prune
[[ $BSTOW_STATUS -eq 0 ]] || fail 'restow failed before foreign stale-link test'
rm "$stow_dir/prune/.config/prune/replaced"
unlink "$target_dir/.config/prune/replaced"
ln -s "$target_dir/other" "$target_dir/.config/prune/replaced"
run_bstow --dir "$stow_dir" --target "$target_dir" restow prune
[[ $BSTOW_STATUS -eq 0 ]] || fail 'restow failed while preserving a foreign stale link'
assert_link_target "$target_dir/.config/prune/replaced" "$target_dir/other"

touch "$stow_dir/prune/.config/prune/regular"
run_bstow --dir "$stow_dir" --target "$target_dir" restow prune
[[ $BSTOW_STATUS -eq 0 ]] || fail 'restow failed before stale regular-file test'
rm "$stow_dir/prune/.config/prune/regular"
unlink "$target_dir/.config/prune/regular"
printf 'keep me\n' >"$target_dir/.config/prune/regular"
run_bstow --dir "$stow_dir" --target "$target_dir" restow prune
[[ $BSTOW_STATUS -eq 0 ]] || fail 'restow failed while preserving a stale regular file'
[[ -f $target_dir/.config/prune/regular && ! -L $target_dir/.config/prune/regular ]] || fail 'restow removed a stale regular file'
[[ $(<"$target_dir/.config/prune/regular") == 'keep me' ]] || fail 'restow changed a stale regular file'

alias_link=$target_dir/.config/prune/alias
ln -s "$stow_dir/prune/.config/prune/current" "$alias_link"
run_bstow --dir "$stow_dir" --target "$target_dir" restow prune
[[ $BSTOW_STATUS -eq 0 ]] || fail 'restow failed while preserving a link at an unmanaged destination'
assert_link_target "$alias_link" "$stow_dir/prune/.config/prune/current"

mkdir -p "$stow_dir/branch/.config/one" "$stow_dir/branch/.config/two"
touch "$stow_dir/branch/.config/one/current" "$stow_dir/branch/.config/two/obsolete"
run_bstow --dir "$stow_dir" --target "$target_dir" stow branch
[[ $BSTOW_STATUS -eq 0 ]] || fail 'initial multi-branch package stow failed'
branch_obsolete=$target_dir/.config/two/obsolete
assert_link_target "$branch_obsolete" "$stow_dir/branch/.config/two/obsolete"
rm -r "$stow_dir/branch/.config/two"
run_bstow --dir "$stow_dir" --target "$target_dir" restow branch
[[ $BSTOW_STATUS -eq 0 ]] || fail 'restow failed after an entire source branch was deleted'
[[ ! -e $branch_obsolete && ! -L $branch_obsolete ]] || fail 'restow retained a link from a deleted source branch'
assert_link_target "$target_dir/.config/one/current" "$stow_dir/branch/.config/one/current"

alternate_stow_dir=$test_root/home/alternate-repo
mkdir -p "$alternate_stow_dir/branch/.config/one"
touch "$alternate_stow_dir/branch/.config/one/current"
run_bstow --dir "$alternate_stow_dir" --target "$target_dir" restow branch
[[ $BSTOW_STATUS -ne 0 ]] || fail 'restow adopted another package source without force'
assert_contains "$BSTOW_OUTPUT" 'Package state belongs to another source'
assert_link_target "$target_dir/.config/one/current" "$stow_dir/branch/.config/one/current"

run_bstow --force --dir "$alternate_stow_dir" --target "$target_dir" restow branch
[[ $BSTOW_STATUS -eq 0 ]] || fail 'forced restow did not adopt another package source'
assert_link_target "$target_dir/.config/one/current" "$alternate_stow_dir/branch/.config/one/current"

mkdir -p "$stow_dir/folded/.config/folded/skins" "$alternate_stow_dir/folded/.config/folded/skins" "$target_dir/.config/folded"
printf 'old\n' > "$stow_dir/folded/.config/folded/skins/theme.yaml"
printf 'new\n' > "$alternate_stow_dir/folded/.config/folded/skins/theme.yaml"
printf 'added\n' > "$alternate_stow_dir/folded/.config/folded/skins/added.yaml"
folded_dir=$target_dir/.config/folded/skins
ln -s "$stow_dir/folded/.config/folded/skins" "$folded_dir"

run_bstow --dir "$alternate_stow_dir" --target "$target_dir" restow folded
[[ $BSTOW_STATUS -ne 0 ]] || fail 'restow adopted a foreign parent-directory symlink without force'
assert_link_target "$folded_dir" "$stow_dir/folded/.config/folded/skins"

run_bstow --dry-run --force --dir "$alternate_stow_dir" --target "$target_dir" restow folded
[[ $BSTOW_STATUS -eq 0 ]] || fail 'forced dry-run rejected a foreign parent-directory symlink'
assert_contains "$BSTOW_OUTPUT" "Would replace directory symlink: $folded_dir"
assert_link_target "$folded_dir" "$stow_dir/folded/.config/folded/skins"

run_bstow --force --dir "$alternate_stow_dir" --target "$target_dir" restow folded
[[ $BSTOW_STATUS -eq 0 ]] || fail 'forced restow did not unfold a foreign parent-directory symlink'
[[ -d $folded_dir && ! -L $folded_dir ]] || fail 'forced restow did not replace the directory symlink with a real directory'
assert_link_target "$folded_dir/theme.yaml" "$alternate_stow_dir/folded/.config/folded/skins/theme.yaml"
assert_link_target "$folded_dir/added.yaml" "$alternate_stow_dir/folded/.config/folded/skins/added.yaml"
[[ $(<"$stow_dir/folded/.config/folded/skins/theme.yaml") == 'old' ]] || fail 'forced restow modified the previous package source'

mkdir -p "$alternate_stow_dir/unsafe/.config/unsafe" "$test_root/shared-config"
touch "$alternate_stow_dir/unsafe/.config/unsafe/settings.yaml" "$test_root/shared-config/settings.yaml"
unsafe_dir=$target_dir/.config/unsafe
ln -s "$test_root/shared-config" "$unsafe_dir"
run_bstow --force --dir "$alternate_stow_dir" --target "$target_dir" restow unsafe
[[ $BSTOW_STATUS -ne 0 ]] || fail 'forced restow replaced an arbitrary parent-directory symlink'
assert_contains "$BSTOW_OUTPUT" 'Refusing to replace parent symlink outside a matching package tree'
assert_link_target "$unsafe_dir" "$test_root/shared-config"

printf 'bstow tests passed\n'
