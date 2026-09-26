#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
bstow=$repo_dir/bstow
failure_fixture=$repo_dir/tests/fixtures/bstow/fail-command
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

run_bstow_with_failure() {
    local command=$1
    shift
    local shim_dir=$test_root/shims/$command

    mkdir -p "$shim_dir"
    ln -sf "$failure_fixture" "$shim_dir/$command"
    PATH="$shim_dir:$PATH" BSTOW_FAIL_STATUS=73 run_bstow "$@"
}

package_state_file() {
    local package=$1
    find "$test_root/state" -maxdepth 1 -type f -name "$package-*.links" -print -quit
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
bash_state=$(package_state_file bash)
bash_state_before=$(cksum <"$bash_state")

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
[[ $(cksum <"$bash_state") == "$bash_state_before" ]] || fail 'dry-run changed package state'

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
printf 'old only\n' > "$stow_dir/folded/.config/folded/skins/old-only.yaml"
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
replacement_count=$(grep -Fc "Would replace directory symlink: $folded_dir" <<< "$BSTOW_OUTPUT")
[[ $replacement_count -eq 1 ]] || fail "forced dry-run reported the same directory replacement $replacement_count times"
assert_link_target "$folded_dir" "$stow_dir/folded/.config/folded/skins"

run_bstow --force --dir "$alternate_stow_dir" --target "$target_dir" restow folded
[[ $BSTOW_STATUS -eq 0 ]] || fail 'forced restow did not unfold a foreign parent-directory symlink'
[[ -d $folded_dir && ! -L $folded_dir ]] || fail 'forced restow did not replace the directory symlink with a real directory'
assert_link_target "$folded_dir/theme.yaml" "$alternate_stow_dir/folded/.config/folded/skins/theme.yaml"
assert_link_target "$folded_dir/added.yaml" "$alternate_stow_dir/folded/.config/folded/skins/added.yaml"
[[ $(<"$stow_dir/folded/.config/folded/skins/theme.yaml") == 'old' ]] || fail 'forced restow modified the previous package source'
[[ ! -e $folded_dir/old-only.yaml && ! -L $folded_dir/old-only.yaml ]] || fail 'forced restow retained a path that exists only in the previous package source'
[[ $(<"$stow_dir/folded/.config/folded/skins/old-only.yaml") == 'old only' ]] || fail 'forced restow modified an old-only source file'

mkdir -p "$alternate_stow_dir/same/.config/same/skins" "$target_dir/.config/same"
printf 'current\n' > "$alternate_stow_dir/same/.config/same/skins/theme.yaml"
same_dir=$target_dir/.config/same/skins
ln -s "$alternate_stow_dir/same/.config/same/skins" "$same_dir"
run_bstow --dir "$alternate_stow_dir" --target "$target_dir" stow same
[[ $BSTOW_STATUS -eq 0 ]] || fail 'stow rejected a parent-directory symlink to the current package source'
[[ -d $same_dir && ! -L $same_dir ]] || fail 'stow did not unfold a current-source directory symlink'
assert_link_target "$same_dir/theme.yaml" "$alternate_stow_dir/same/.config/same/skins/theme.yaml"

mkdir -p "$alternate_stow_dir/unsafe/.config/unsafe" "$test_root/shared-config"
touch "$alternate_stow_dir/unsafe/.config/unsafe/settings.yaml" "$test_root/shared-config/settings.yaml"
unsafe_dir=$target_dir/.config/unsafe
ln -s "$test_root/shared-config" "$unsafe_dir"
run_bstow --force --dir "$alternate_stow_dir" --target "$target_dir" restow unsafe
[[ $BSTOW_STATUS -ne 0 ]] || fail 'forced restow replaced an arbitrary parent-directory symlink'
assert_contains "$BSTOW_OUTPUT" 'Refusing to replace parent symlink outside a matching package tree'
assert_link_target "$unsafe_dir" "$test_root/shared-config"

mkdir -p "$stow_dir/source-shape/empty"
printf 'managed\n' >"$stow_dir/source-shape/managed"
ln -s managed "$stow_dir/source-shape/ignored-link"
run_bstow --dir "$stow_dir" --target "$target_dir" stow source-shape
[[ $BSTOW_STATUS -eq 0 ]] || fail 'source package shape test failed'
assert_link_target "$target_dir/managed" "$stow_dir/source-shape/managed"
[[ ! -e $target_dir/ignored-link && ! -L $target_dir/ignored-link ]] || fail 'source symlink entry was managed'
[[ ! -e $target_dir/empty && ! -L $target_dir/empty ]] || fail 'empty source directory was managed'
[[ ! -e $target_dir/.local/state/bstow ]] || fail 'custom state run wrote to the default state directory'

mkdir -p "$stow_dir/force-regular"
printf 'source\n' >"$stow_dir/force-regular/protected"
printf 'local\n' >"$target_dir/protected"
run_bstow --force --dir "$stow_dir" --target "$target_dir" stow force-regular
[[ $BSTOW_STATUS -ne 0 ]] || fail 'force replaced a regular target file'
[[ -f $target_dir/protected && ! -L $target_dir/protected ]] || fail 'force changed a regular target file type'
[[ $(<"$target_dir/protected") == local ]] || fail 'force changed a regular target file'

mkdir -p "$test_root/outside-package"
printf 'outside\n' >"$test_root/outside-package/traversed"
run_bstow --dir "$stow_dir" --target "$target_dir" stow ../../outside-package
[[ $BSTOW_STATUS -ne 0 ]] || fail 'package argument escaped the stow directory'
assert_contains "$BSTOW_OUTPUT" 'Invalid package name'
[[ ! -e $target_dir/traversed && ! -L $target_dir/traversed ]] || fail 'traversal package changed the target'

mkdir -p "$test_root/symlink-package-source"
printf 'outside\n' >"$test_root/symlink-package-source/symlinked-root-file"
ln -s "$test_root/symlink-package-source" "$stow_dir/symlink-package"
run_bstow --dir "$stow_dir" --target "$target_dir" stow symlink-package
[[ $BSTOW_STATUS -ne 0 ]] || fail 'symlinked package root was accepted'
assert_contains "$BSTOW_OUTPUT" 'Package directory must not be a symlink'
[[ ! -e $target_dir/symlinked-root-file && ! -L $target_dir/symlinked-root-file ]] || fail 'symlinked package root changed the target'

mkdir -p "$stow_dir/changed-parent/.config/changed-parent" "$test_root/changed-parent-foreign"
printf 'source\n' >"$stow_dir/changed-parent/.config/changed-parent/settings"
printf 'foreign\n' >"$test_root/changed-parent-foreign/settings"
run_bstow --dry-run --dir "$stow_dir" --target "$target_dir" stow changed-parent
[[ $BSTOW_STATUS -eq 0 ]] || fail 'changed-parent dry-run setup failed'
mkdir -p "$target_dir/.config"
ln -s "$test_root/changed-parent-foreign" "$target_dir/.config/changed-parent"
run_bstow --force --dir "$stow_dir" --target "$target_dir" stow changed-parent
[[ $BSTOW_STATUS -ne 0 ]] || fail 'stow wrote through a changed foreign parent symlink'
assert_link_target "$target_dir/.config/changed-parent" "$test_root/changed-parent-foreign"
[[ $(<"$test_root/changed-parent-foreign/settings") == foreign ]] || fail 'changed foreign parent content was modified'

mkdir -p "$stow_dir/missing-source"
printf 'source\n' >"$stow_dir/missing-source/missing-source-file"
run_bstow --dir "$stow_dir" --target "$target_dir" stow missing-source
[[ $BSTOW_STATUS -eq 0 ]] || fail 'missing-source setup failed'
missing_source_state=$(package_state_file missing-source)
mv "$stow_dir/missing-source" "$test_root/missing-source-saved"
run_bstow --dir "$stow_dir" --target "$target_dir" unstow missing-source
[[ $BSTOW_STATUS -ne 0 ]] || fail 'unstow accepted a completely missing source package'
assert_link_target "$target_dir/missing-source-file" "$stow_dir/missing-source/missing-source-file"
[[ -f $missing_source_state ]] || fail 'missing source package removed ownership state'

for corrupt_case in invalid-header unsafe-record truncated-record; do
    mkdir -p "$stow_dir/$corrupt_case/$corrupt_case"
    printf 'one\n' >"$stow_dir/$corrupt_case/$corrupt_case/one"
    printf 'two\n' >"$stow_dir/$corrupt_case/$corrupt_case/two"
    run_bstow --dir "$stow_dir" --target "$target_dir" stow "$corrupt_case"
    [[ $BSTOW_STATUS -eq 0 ]] || fail "$corrupt_case setup failed"
done

invalid_header_state=$(package_state_file invalid-header)
printf '%s\0%s\0' relative/source invalid-header/one >"$invalid_header_state"
run_bstow --dir "$stow_dir" --target "$target_dir" unstow invalid-header
[[ $BSTOW_STATUS -ne 0 ]] || fail 'relative state source header was accepted'
assert_link_target "$target_dir/invalid-header/one" "$stow_dir/invalid-header/invalid-header/one"
[[ -f $invalid_header_state ]] || fail 'invalid source header removed state'

unsafe_record_state=$(package_state_file unsafe-record)
printf '%s\0%s\0%s\0' "$stow_dir/unsafe-record" unsafe-record/one ../outside >"$unsafe_record_state"
run_bstow --dir "$stow_dir" --target "$target_dir" unstow unsafe-record
[[ $BSTOW_STATUS -ne 0 ]] || fail 'unsafe later state record was accepted'
assert_link_target "$target_dir/unsafe-record/one" "$stow_dir/unsafe-record/unsafe-record/one"
assert_link_target "$target_dir/unsafe-record/two" "$stow_dir/unsafe-record/unsafe-record/two"
[[ -f $unsafe_record_state ]] || fail 'unsafe state record removed state'

truncated_record_state=$(package_state_file truncated-record)
printf '%s\0%s\0%s' "$stow_dir/truncated-record" truncated-record/one truncated-record/two >"$truncated_record_state"
rm "$stow_dir/truncated-record/truncated-record/two"
run_bstow --dir "$stow_dir" --target "$target_dir" unstow truncated-record
[[ $BSTOW_STATUS -ne 0 ]] || fail 'unterminated final state record was accepted'
assert_link_target "$target_dir/truncated-record/one" "$stow_dir/truncated-record/truncated-record/one"
assert_link_target "$target_dir/truncated-record/two" "$stow_dir/truncated-record/truncated-record/two"
[[ -f $truncated_record_state ]] || fail 'truncated state was removed'

mkdir -p "$stow_dir/find-failure"
printf 'source\n' >"$stow_dir/find-failure/find-failure-file"
run_bstow_with_failure find --dir "$stow_dir" --target "$target_dir" stow find-failure
[[ $BSTOW_STATUS -ne 0 ]] || fail 'failed package enumeration was treated as an empty package'
assert_contains "$BSTOW_OUTPUT" 'Failed to enumerate'
[[ ! -e $target_dir/find-failure-file && ! -L $target_dir/find-failure-file ]] || fail 'failed enumeration changed the target'
[[ -z $(package_state_file find-failure) ]] || fail 'failed enumeration wrote ownership state'

mkdir -p "$stow_dir/mkdir-failure/nested"
printf 'source\n' >"$stow_dir/mkdir-failure/nested/mkdir-failure-file"
run_bstow_with_failure mkdir --dir "$stow_dir" --target "$target_dir" stow mkdir-failure
[[ $BSTOW_STATUS -ne 0 ]] || fail 'failed target directory creation returned success'
[[ ! -e $target_dir/nested/mkdir-failure-file && ! -L $target_dir/nested/mkdir-failure-file ]] || fail 'mkdir failure created a target link'
[[ -z $(package_state_file mkdir-failure) ]] || fail 'mkdir failure wrote ownership state'

mkdir -p "$stow_dir/ln-failure"
printf 'source\n' >"$stow_dir/ln-failure/ln-failure-file"
run_bstow_with_failure ln --dir "$stow_dir" --target "$target_dir" stow ln-failure
[[ $BSTOW_STATUS -ne 0 ]] || fail 'failed link creation returned success'
[[ $BSTOW_OUTPUT != *'Linked:'* ]] || fail 'failed link creation reported success'
[[ ! -e $target_dir/ln-failure-file && ! -L $target_dir/ln-failure-file ]] || fail 'ln failure created a target link'
[[ -z $(package_state_file ln-failure) ]] || fail 'ln failure wrote ownership state'

mkdir -p "$stow_dir/unlink-failure"
printf 'source\n' >"$stow_dir/unlink-failure/unlink-failure-file"
run_bstow --dir "$stow_dir" --target "$target_dir" stow unlink-failure
[[ $BSTOW_STATUS -eq 0 ]] || fail 'unlink failure setup failed'
unlink_failure_state=$(package_state_file unlink-failure)
run_bstow_with_failure unlink --dir "$stow_dir" --target "$target_dir" unstow unlink-failure
[[ $BSTOW_STATUS -ne 0 ]] || fail 'failed link removal returned success'
[[ $BSTOW_OUTPUT != *'Removed:'* ]] || fail 'failed link removal reported success'
assert_link_target "$target_dir/unlink-failure-file" "$stow_dir/unlink-failure/unlink-failure-file"
[[ -f $unlink_failure_state ]] || fail 'unlink failure removed ownership state'

mkdir -p "$stow_dir/foreign-unlink-failure"
printf 'source\n' >"$stow_dir/foreign-unlink-failure/foreign-unlink-failure-file"
printf 'foreign\n' >"$test_root/foreign-unlink-target"
ln -s "$test_root/foreign-unlink-target" "$target_dir/foreign-unlink-failure-file"
run_bstow_with_failure unlink --force --dir "$stow_dir" --target "$target_dir" stow foreign-unlink-failure
[[ $BSTOW_STATUS -ne 0 ]] || fail 'failed foreign-link removal returned success'
assert_link_target "$target_dir/foreign-unlink-failure-file" "$test_root/foreign-unlink-target"
[[ $(<"$test_root/foreign-unlink-target") == foreign ]] || fail 'foreign target changed after unlink failure'

mkdir -p "$stow_dir/state-write-failure"
printf 'source\n' >"$stow_dir/state-write-failure/state-write-failure-file"
run_bstow_with_failure mv --dir "$stow_dir" --target "$target_dir" stow state-write-failure
[[ $BSTOW_STATUS -ne 0 ]] || fail 'failed state replacement returned success'
assert_link_target "$target_dir/state-write-failure-file" "$stow_dir/state-write-failure/state-write-failure-file"
[[ -z $(package_state_file state-write-failure) ]] || fail 'failed state replacement published ownership state'
[[ -z $(find "$test_root/state" -maxdepth 1 -type f -name '.bstow-state.*' -print -quit) ]] || fail 'failed state replacement left a temporary file'
run_bstow --dir "$stow_dir" --target "$target_dir" stow state-write-failure
[[ $BSTOW_STATUS -eq 0 ]] || fail 'retry after failed state replacement did not recover'
[[ -n $(package_state_file state-write-failure) ]] || fail 'retry after failed state replacement did not record ownership'

printf 'bstow tests passed\n'
