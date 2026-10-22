#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

test_home=$test_root/integrity-home
mkdir -p "$test_home"
run_manager install "$artifact_one" >/dev/null

collision=$test_root/collision.tar.gz
make_artifact "$commit_one" collision "$collision"
set +e
collision_output=$(run_manager install "$collision" 2>&1)
collision_status=$?
set -e
[[ $collision_status -ne 0 && $collision_output == *'release ID collision'* ]] ||
  fail 'same-ID different-content collision was accepted'

metadata_commit=6666666666666666666666666666666666666666
metadata_id=dotfiles-${metadata_commit:0:12}
metadata_artifact=$test_root/metadata-unknown.tar.gz
make_artifact "$metadata_commit" metadata-unknown "$metadata_artifact"
printf 'FORMAT_VERSION=1\n' >>"$test_root/stage-metadata-unknown/$metadata_id/release.env"
repack_artifact metadata-unknown "$metadata_id" "$metadata_artifact"
set +e
metadata_output=$(run_manager install "$metadata_artifact" 2>&1)
metadata_status=$?
set -e
[[ $metadata_status -ne 0 &&
  $metadata_output == *'unknown release metadata key: FORMAT_VERSION'* ]] ||
  fail 'obsolete release metadata marker was accepted'
assert_link "$test_home/dotfiles-releases/current" "$id_one"
[[ ! -e $test_home/dotfiles-releases/$metadata_id ]] ||
  fail 'invalid metadata package was retained'

duplicate_commit=7777777777777777777777777777777777777777
duplicate_id=dotfiles-${duplicate_commit:0:12}
duplicate_artifact=$test_root/metadata-duplicate.tar.gz
make_artifact "$duplicate_commit" metadata-duplicate "$duplicate_artifact"
printf 'TASK_VERSION=1.0\n' >>"$test_root/stage-metadata-duplicate/$duplicate_id/release.env"
repack_artifact metadata-duplicate "$duplicate_id" "$duplicate_artifact"
set +e
duplicate_output=$(run_manager install "$duplicate_artifact" 2>&1)
duplicate_status=$?
set -e
[[ $duplicate_status -ne 0 &&
  $duplicate_output == *'duplicate release metadata key: TASK_VERSION'* ]] ||
  fail 'duplicate release metadata field was accepted'
assert_link "$test_home/dotfiles-releases/current" "$id_one"
[[ ! -e $test_home/dotfiles-releases/$duplicate_id ]] ||
  fail 'duplicate metadata package was retained'

missing_commit=8888888888888888888888888888888888888888
missing_id=dotfiles-${missing_commit:0:12}
missing_artifact=$test_root/metadata-missing.tar.gz
make_artifact "$missing_commit" metadata-missing "$missing_artifact"
sed -i '/^TASK_VERSION=/d' "$test_root/stage-metadata-missing/$missing_id/release.env"
repack_artifact metadata-missing "$missing_id" "$missing_artifact"
set +e
missing_metadata_output=$(run_manager install "$missing_artifact" 2>&1)
missing_metadata_status=$?
set -e
[[ $missing_metadata_status -ne 0 &&
  $missing_metadata_output == *'missing release metadata key: TASK_VERSION'* ]] ||
  fail 'missing release metadata field was accepted'
assert_link "$test_home/dotfiles-releases/current" "$id_one"
[[ ! -e $test_home/dotfiles-releases/$missing_id ]] ||
  fail 'missing metadata package was retained'

malicious_root=$test_root/malicious
metadata_marker=$test_root/metadata-executed
mkdir -p "$malicious_root/dotfiles-aaaaaaaaaaaa"
# shellcheck disable=SC2016
printf 'RELEASE_ID=$(touch -- %q)\n' "$metadata_marker" \
  >"$malicious_root/dotfiles-aaaaaaaaaaaa/release.env"
printf '' >"$malicious_root/dotfiles-aaaaaaaaaaaa/SHA256SUMS"
tar -C "$malicious_root" -czf "$test_root/malicious.tar.gz" dotfiles-aaaaaaaaaaaa
set +e
run_manager install "$test_root/malicious.tar.gz" >/dev/null 2>&1
malicious_status=$?
set -e
[[ $malicious_status -ne 0 ]] || fail 'malicious metadata was accepted'
[[ ! -e $metadata_marker ]] || fail 'release metadata was executed'

unsafe_link_root=$test_root/unsafe-link
mkdir -p "$unsafe_link_root/dotfiles-aaaaaaaaaaaa"
ln -s ../../outside "$unsafe_link_root/dotfiles-aaaaaaaaaaaa/escape"
tar -C "$unsafe_link_root" -czf "$test_root/unsafe-link.tar.gz" dotfiles-aaaaaaaaaaaa
set +e
unsafe_link_output=$(run_manager install "$test_root/unsafe-link.tar.gz" 2>&1)
unsafe_link_status=$?
set -e
[[ $unsafe_link_status -ne 0 && $unsafe_link_output == *'archive link escapes its root'* ]] ||
  fail 'escaping archive symlink was accepted'

corrupt_root=$test_root/corrupt
mkdir "$corrupt_root"
tar -xzf "$artifact_three" -C "$corrupt_root"
printf 'corrupt\n' >>"$corrupt_root/$id_three/config/nvim2/init.lua"
tar -C "$corrupt_root" -czf "$test_root/corrupt.tar.gz" "$id_three"
set +e
corrupt_output=$(run_manager install "$test_root/corrupt.tar.gz" 2>&1)
corrupt_status=$?
set -e
[[ $corrupt_status -ne 0 && $corrupt_output == *'archive checksums do not match'* ]] ||
  fail 'artifact with a corrupt payload was accepted'

printf 'dotfiles_release: integrity passed\n'
