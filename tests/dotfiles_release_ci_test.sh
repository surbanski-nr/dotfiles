#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'find "$test_root" -depth -delete' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

source_dir=$test_root/source
mkdir -p "$source_dir/scripts"
cp "$repo_dir/release.env" "$source_dir/release.env"
printf '#!/bin/sh\nexit 0\n' >"$source_dir/scripts/build-dotfiles-release"
printf '#!/bin/sh\nexit 0\n' >"$source_dir/scripts/setup-lib"
printf 'fixture config\n' >"$source_dir/system.env"
git -C "$source_dir" init -q
git -C "$source_dir" add .
GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
  GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid \
  git -C "$source_dir" commit -qm fixture
export TEST_COMMIT
TEST_COMMIT=$(git -C "$source_dir" rev-parse HEAD)
export COMMIT_SHA=$TEST_COMMIT
export RELEASE_TAG=dotfiles-${TEST_COMMIT:0:12}
export PLATFORM=debian-13-x86_64
export REPOSITORY=fixture/repo
export RUNNER_TEMP=$test_root/runner
export GITHUB_OUTPUT=$test_root/outputs
export GITHUB_STEP_SUMMARY=$test_root/summary
export GITHUB_RUN_ID=fixture
export GITHUB_RUN_ATTEMPT=1
export EVENT_NAME=workflow_dispatch
export INPUT_RELEASE_TAG=$RELEASE_TAG
export TAG_NAME=$RELEASE_TAG
export TEST_RELEASE_ASSETS=$test_root/assets
export TEST_UPLOAD_LOG=$test_root/uploads
export TEST_DOCKER_LOG=$test_root/docker.log
mkdir -p "$RUNNER_TEMP" "$TEST_RELEASE_ASSETS" "$test_root/empty-home" "$test_root/bin"
ln -s "$repo_dir/tests/fixtures/dotfiles-release-ci/gh" "$test_root/bin/gh"
ln -s "$repo_dir/tests/fixtures/dotfiles-release-ci/docker" "$test_root/bin/docker"
export PATH="$test_root/bin:$PATH"
archive=$RELEASE_TAG-$PLATFORM.tar.gz

make_archive() {
  local stage=$test_root/payload platform=${1:-$PLATFORM}
  mkdir -p "$stage/$RELEASE_TAG"
  printf 'fixture payload\n' >"$stage/$RELEASE_TAG/payload"
  printf '#!/bin/sh\nexit 99\n' >"$stage/$RELEASE_TAG/dotfiles-release"
  printf 'fixture build manifest\n' >"$stage/$RELEASE_TAG/build-manifest.txt"
  printf '%s\n' \
    "RELEASE_ID=$RELEASE_TAG" "PLATFORM_ID=$platform" "SOURCE_COMMIT=$TEST_COMMIT" \
    'SOURCE_TREE=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' \
    'BUILDER_IMAGE=fixture@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc' \
    'NVIM_VERSION=v1.0' 'NODE_VERSION=1.0' 'NPM_VERSION=1.0' 'NODE_UPSTREAM_NPM_VERSION=1.0' \
    'PYTHON_VERSION=3.12.12' 'PYTHON_BUILD=20260127' 'TMUX_VERSION=1.0' 'RG_VERSION=1.0' \
    'FZF_VERSION=1.0' 'ZOXIDE_VERSION=1.0' 'K9S_VERSION=1.0' 'KUBECTX_VERSION=1.0' \
    'OMP_VERSION=1.0' 'TASK_VERSION=1.0' 'TERRAFORM_VERSION=1.0' 'KUBECTL_VERSIONS=1.0' 'HELM_VERSIONS=1.0' \
    'OFFLINE_TOOLS=nvim,nodejs,python,rg,tmux,oh-my-posh,k9s,zoxide,kubectx,kubens,task,fzf,terraform,kubectl,helm' \
    'PAYLOAD_PATHS=bin,config,dotfiles,python-locks,python-wheelhouse,share,tools' \
    >"$stage/$RELEASE_TAG/release.env"
  repack_archive
}

repack_archive() {
  local stage=$test_root/payload
  (cd "$stage/$RELEASE_TAG" && sha256sum payload dotfiles-release build-manifest.txt release.env >SHA256SUMS)
  tar -C "$stage" -czf "$test_root/$archive" "$RELEASE_TAG"
}

run_ci() { bash "$repo_dir/scripts/dotfiles-release-ci" "$@"; }
run_preflight() { : >"$GITHUB_OUTPUT"; run_ci preflight; }
matrix() { sed -n 's/^platforms=//p' "$GITHUB_OUTPUT"; }

make_archive
root=$(HOME="$test_root/empty-home" bash "$repo_dir/scripts/dotfiles-release" inspect "$PLATFORM" "$test_root/$archive" "$COMMIT_SHA")
[[ $root == "$RELEASE_TAG" && -z $(find "$test_root/empty-home" -mindepth 1 -print -quit) ]] ||
  fail 'archive inspection changed HOME or did not return its identity'
run_preflight
matrix | jq -e 'length == 4 and all(.[]; .build_archive == true)' >/dev/null || fail 'missing archives did not select four builds'
grep -Fx 'should_run=true' "$GITHUB_OUTPUT" >/dev/null || fail 'missing assets did not schedule work'

TEST_RELEASE_ERROR=404 run_preflight >"$test_root/absent.log"
grep -Fx 'should_run=false' "$GITHUB_OUTPUT" >/dev/null || fail 'missing release was not skipped'
if TEST_RELEASE_ERROR=403 run_preflight >"$test_root/denied.log" 2>&1; then fail 'API permission failure was hidden'; fi
if INPUT_RELEASE_TAG=bad-tag run_preflight >"$test_root/tag.log" 2>&1; then fail 'invalid tag was accepted'; fi
if TEST_COMMIT=2222222222222222222222222222222222222222 run_preflight >"$test_root/commit.log" 2>&1; then
  fail 'tag/commit mismatch was accepted'
fi

cp "$test_root/$archive" "$TEST_RELEASE_ASSETS/$archive"
TEST_TAG_TYPE=tag run_preflight
matrix | jq -e 'length == 4 and .[0].build_archive == false and all(.[1:][]; .build_archive == true)' >/dev/null ||
  fail 'missing checksum scheduled an archive rebuild'

run_ci publish "$test_root/nonexistent-output"
[[ $(<"$TEST_UPLOAD_LOG") == "$archive.sha256" ]] || fail 'checksum repair uploaded an existing archive'
(cd "$TEST_RELEASE_ASSETS" && sha256sum --check --strict "$archive.sha256" >/dev/null)
run_preflight
matrix | jq -e 'length == 3 and all(.[]; .platform != "debian-13-x86_64")' >/dev/null || fail 'complete platform was not skipped'
upload_before=$(sha256sum "$TEST_UPLOAD_LOG")
run_ci publish "$test_root/nonexistent-output"
[[ $(sha256sum "$TEST_UPLOAD_LOG") == "$upload_before" ]] || fail 'complete assets were uploaded twice'

printf 'invalid checksum\n' >"$TEST_RELEASE_ASSETS/$archive.sha256"
if run_preflight >"$test_root/bad-checksum.log" 2>&1; then fail 'preflight accepted a mismatched sidecar'; fi
if run_ci publish "$test_root/nonexistent-output" >"$test_root/bad-publish.log" 2>&1; then fail 'publish replaced a mismatched sidecar'; fi
find "$TEST_RELEASE_ASSETS" -maxdepth 1 -type f -delete

make_archive amzn-2023-x86_64
cp "$test_root/$archive" "$TEST_RELEASE_ASSETS/$archive"
if run_preflight >"$test_root/platform.log" 2>&1; then fail 'wrong-platform archive was accepted'; fi
grep -F 'release is not for debian-13-x86_64' "$test_root/platform.log" >/dev/null || fail 'platform mismatch was not identified'

make_archive
ln -s "$test_root/outside" "$test_root/payload/$RELEASE_TAG/escape"
repack_archive
cp "$test_root/$archive" "$TEST_RELEASE_ASSETS/$archive"
if run_preflight >"$test_root/escape.log" 2>&1; then fail 'absolute escaping symlink was accepted'; fi
[[ ! -e $test_root/outside ]] || fail 'unsafe archive wrote outside its root'
unlink "$test_root/payload/$RELEASE_TAG/escape"
tar -C "$test_root/payload" --transform="s|$RELEASE_TAG/payload|$RELEASE_TAG/../outside|" \
  -czf "$TEST_RELEASE_ASSETS/$archive" "$RELEASE_TAG"
if run_preflight >"$test_root/traversal.log" 2>&1; then fail 'archive path traversal was accepted'; fi
grep -F 'unsafe archive member' "$test_root/traversal.log" >/dev/null || fail 'traversal was not rejected before extraction'
[[ ! -e $test_root/outside ]] || fail 'traversal wrote outside the archive root'

find "$TEST_RELEASE_ASSETS" -maxdepth 1 -type f -delete
make_archive
mkdir -p "$test_root/output"
cp "$test_root/$archive" "$test_root/output/$archive"
: >"$TEST_UPLOAD_LOG"
set +e
TEST_UPLOAD_FAIL_AFTER_ARCHIVE=1 run_ci publish "$test_root/output" >"$test_root/interrupted.log" 2>&1
upload_status=$?
set -e
[[ $upload_status -eq 77 && -f $TEST_RELEASE_ASSETS/$archive && ! -e $TEST_RELEASE_ASSETS/$archive.sha256 ]] ||
  fail 'partial upload did not leave the expected recoverable archive'
run_preflight
matrix | jq -e '.[0].build_archive == false' >/dev/null || fail 'partial upload retry would rebuild the archive'
run_ci publish "$test_root/output"
[[ $(grep -Fxc "$archive" "$TEST_UPLOAD_LOG") -eq 1 && $(grep -Fxc "$archive.sha256" "$TEST_UPLOAD_LOG") -eq 1 ]] ||
  fail 'partial upload retry did not publish each asset exactly once'

for platform in ubuntu-24.04-x86_64 ubuntu-26.04-x86_64 amzn-2023-x86_64; do
  make_archive "$platform"
  asset=$RELEASE_TAG-$platform.tar.gz
  cp "$test_root/$archive" "$TEST_RELEASE_ASSETS/$asset"
  (cd "$TEST_RELEASE_ASSETS" && sha256sum "$asset" >"$asset.sha256")
done
run_preflight
[[ $(matrix) == '[]' ]] || fail 'complete release scheduled redundant work'
grep -Fx 'should_run=false' "$GITHUB_OUTPUT" >/dev/null || fail 'complete release did not skip work'

make_archive
export TEST_BUILD_ARCHIVE=$test_root/$archive
run_ci build "$source_dir" "$test_root/output" >"$test_root/build.log"
grep -F 'fixture offline health succeeded' "$RUNNER_TEMP/dotfiles-evidence/$PLATFORM/offline-verify.log" >/dev/null ||
  fail 'build did not perform ordinary-user offline qualification'
for file in build.log prepare-runtime.log release.env build-manifest.txt archive.sha256; do
  [[ -s $RUNNER_TEMP/dotfiles-evidence/$PLATFORM/$file ]] || fail 'build evidence was not preserved'
done
for stage in BUILD VERIFY PREPARE; do
  failure_runner=$test_root/runner-$stage
  mkdir -p "$failure_runner"
  : >"$TEST_DOCKER_LOG"
  set +e
  env "TEST_${stage}_FAIL=1" RUNNER_TEMP="$failure_runner" \
    bash "$repo_dir/scripts/dotfiles-release-ci" build "$source_dir" "$test_root/output" \
    >"$test_root/failure-$stage.log" 2>&1
  failure_status=$?
  set -e
  case $stage in
    BUILD) expected=81; failure_log=build.log ;;
    VERIFY) expected=82; failure_log=offline-verify.log ;;
    PREPARE) expected=83; failure_log=prepare-runtime.log ;;
  esac
  [[ $failure_status -eq $expected ]] || fail "build hid $stage failure"
  grep -F 'failure' "$failure_runner/dotfiles-evidence/$PLATFORM/$failure_log" >/dev/null ||
    fail "build did not retain $stage failure evidence"
  grep -F 'rm --force dotfiles-builder-fixture-1-debian-13-x86_64' "$TEST_DOCKER_LOG" >/dev/null ||
    fail 'failed build did not clean up its containers'
done

printf 'Dotfiles release CI tests passed\n'
