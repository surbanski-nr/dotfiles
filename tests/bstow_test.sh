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
    if output=$(timeout 10s "$bstow" "$@" 2>&1); then
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

printf 'bstow tests passed\n'
