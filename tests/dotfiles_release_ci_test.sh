#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=dotfiles_release/fixture.sh
source "$repo_dir/tests/dotfiles_release/fixture.sh"
test_root=$(mktemp -d)
cancellation_pid=
cleanup() {
  if [[ -n $cancellation_pid ]]; then
    pkill --signal KILL --session "$cancellation_pid" 2>/dev/null || true
    wait "$cancellation_pid" 2>/dev/null || true
  fi
  find "$test_root" -depth -delete
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

source_dir=$test_root/source
workflow_dir=$test_root/workflow
mkdir -p "$source_dir/scripts" "$workflow_dir/scripts" "$workflow_dir/tests"
cp "$repo_dir/Taskfile.yml" "$source_dir/Taskfile.yml"
cp "$repo_dir/scripts/dotfiles-release-ci" "$source_dir/scripts/dotfiles-release-ci"
cp "$repo_dir/platforms.env" "$source_dir/platforms.env"
# Exercise publication and parallel qualification independently of the currently enabled targets.
cat >>"$source_dir/platforms.env" <<'EOF'
OFFLINE_TEST_PLATFORMS=(
  debian-13-x86_64
  ubuntu-24.04-x86_64
  ubuntu-26.04-x86_64
  amzn-2023-x86_64
)
OFFLINE_RELEASE_PLATFORMS=(
  debian-13-x86_64
  ubuntu-26.04-x86_64
  amzn-2023-x86_64
)
EOF
cp "$source_dir/platforms.env" "$workflow_dir/platforms.env"
cp "$repo_dir/scripts/dotfiles-release-ci" "$workflow_dir/scripts/dotfiles-release-ci"
ln -s "$repo_dir/tools.env" "$workflow_dir/tools.env"
ln -s "$repo_dir/tests/tools" "$workflow_dir/tests/tools"
ln -s "$repo_dir/tests/tools_runner.sh" "$workflow_dir/tests/tools_runner.sh"
for script in "$repo_dir/scripts/dotfiles-release" "$repo_dir/scripts/"*-lib; do
  ln -s "$script" "$workflow_dir/scripts/${script##*/}"
done
printf '%s\n' \
  'DOCKER_IMAGES[debian-13-x86_64]=fixture.invalid/debian:13@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
  >>"$source_dir/platforms.env"
load_config "$source_dir/platforms.env"
test_platform_count=${#OFFLINE_TEST_PLATFORMS[@]}
release_platform_count=${#OFFLINE_RELEASE_PLATFORMS[@]}
build_failure_platform=${OFFLINE_TEST_PLATFORMS[0]}
verify_failure_platform=${OFFLINE_TEST_PLATFORMS[1]}
successful_platform=${OFFLINE_TEST_PLATFORMS[2]}
excluded_release_platform=
for platform in "${OFFLINE_TEST_PLATFORMS[@]}"; do
  if [[ " ${OFFLINE_RELEASE_PLATFORMS[*]} " != *" $platform "* ]]; then
    excluded_release_platform=$platform
    break
  fi
done

cp "$repo_dir/tools.env" "$source_dir/tools.env"
cp "$repo_dir/scripts/dotfiles-release" "$source_dir/scripts/dotfiles-release"
printf '\n# Fixture release snapshot differs from workflow tooling.\n' >>"$source_dir/scripts/dotfiles-release"
printf '#!/bin/sh\nexit 0\n' >"$source_dir/scripts/build-dotfiles-release"
cp "$repo_dir/scripts/build-standalone-script" "$source_dir/scripts/build-standalone-script"
cp "$repo_dir/scripts/"*-lib "$source_dir/scripts/"
cp "$repo_dir/system.env" "$source_dir/system.env"
printf 'SYSTEM_RUNTIME_PACKAGES+=(fixture-release-package)\n' >>"$source_dir/system.env"
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
ln -s "$repo_dir/tests/fixtures/dotfiles-release-ci/nproc" "$test_root/bin/nproc"
export PATH="$test_root/bin:$PATH"
archive=$RELEASE_TAG-$PLATFORM.tar.gz

make_archive() {
  local stage=$test_root/payload platform=${1:-$PLATFORM}
  local include_extra_tools=${2:-false}
  find "$stage" -depth -delete 2>/dev/null || true
  find "$test_root/stage-ci-archive" -depth -delete 2>/dev/null || true
  make_artifact "$TEST_COMMIT" ci-archive "$test_root/ci-fixture.tar.gz" \
    1.0 "$include_extra_tools" "$include_extra_tools" "$include_extra_tools" "$include_extra_tools"
  mv "$test_root/stage-ci-archive" "$stage"
  printf 'fixture payload\n' >"$stage/$RELEASE_TAG/payload"
  bash "$source_dir/scripts/build-standalone-script" "$source_dir" "$stage/$RELEASE_TAG/dotfiles-release"
  printf 'fixture build manifest\n' >"$stage/$RELEASE_TAG/build-manifest.txt"
  sed -i "s/^PLATFORM_ID=.*/PLATFORM_ID=$platform/" "$stage/$RELEASE_TAG/release.env"
  repack_archive
}

repack_archive() {
  local stage=$test_root/payload
  (
    cd "$stage/$RELEASE_TAG"
    find . -type f ! -path './SHA256SUMS' -print0 | LC_ALL=C sort -z |
      xargs -0 sha256sum >"$test_root/ci-SHA256SUMS"
    mv "$test_root/ci-SHA256SUMS" SHA256SUMS
  )
  tar -C "$stage" -czf "$test_root/$archive" "$RELEASE_TAG"
}

run_ci() {
  bash "$workflow_dir/scripts/dotfiles-release-ci" "$@"
}
task_executable=${VALIDATION_TOOLS_DIR:-$repo_dir/bin}/task
run_task_test() {
  "$task_executable" --dir "$source_dir" test "$@"
}
run_preflight() {
  : >"$GITHUB_OUTPUT"
  run_ci preflight
}
matrix() {
  sed -n 's/^platforms=//p' "$GITHUB_OUTPUT"
}

make_archive
root=$(HOME="$test_root/empty-home" bash "$repo_dir/scripts/dotfiles-release" verify "$test_root/$archive")
[[ $root == *"verified $RELEASE_TAG ($PLATFORM)"* && -z $(find "$test_root/empty-home" -mindepth 1 -print -quit) ]] ||
  fail 'archive verification changed HOME or did not report its identity'
run_preflight
matrix | jq -e --argjson count "$release_platform_count" \
  'length == $count and all(.[]; .build_archive == true)' >/dev/null ||
  fail 'missing archives did not select every release build'
grep -Fx 'should_run=true' "$GITHUB_OUTPUT" >/dev/null || fail 'missing assets did not schedule work'
if [[ -n $excluded_release_platform ]]; then
  if PLATFORM=$excluded_release_platform run_ci publish "$test_root/nonexistent-output" \
    >"$test_root/excluded-platform.log" 2>&1; then
    fail 'publish accepted a platform excluded from OFFLINE_RELEASE_PLATFORMS'
  fi
  grep -F "platform is not selected for offline release: $excluded_release_platform" \
    "$test_root/excluded-platform.log" >/dev/null || fail 'excluded release platform was not identified'
fi

cp "$workflow_dir/platforms.env" "$test_root/workflow-config.env"
for invalid in duplicate untested unknown-os missing-image empty; do
  cp "$test_root/workflow-config.env" "$workflow_dir/platforms.env"
  case $invalid in
    duplicate)
      printf 'OFFLINE_TEST_PLATFORMS+=(debian-13-x86_64)\n' >>"$workflow_dir/platforms.env"
      ;;
    untested)
      printf 'OFFLINE_RELEASE_PLATFORMS+=(ubuntu-28.04-x86_64)\n' >>"$workflow_dir/platforms.env"
      ;;
    unknown-os)
      printf '%s\n' \
        'DOCKER_IMAGES[ubuntu-28.04-x86_64]=fixture.invalid/ubuntu:28@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
        'OFFLINE_TEST_PLATFORMS+=(ubuntu-28.04-x86_64)' >>"$workflow_dir/platforms.env"
      ;;
    missing-image)
      printf 'unset "DOCKER_IMAGES[debian-13-x86_64]"\n' >>"$workflow_dir/platforms.env"
      ;;
    empty)
      printf 'OFFLINE_TEST_PLATFORMS=()\nOFFLINE_RELEASE_PLATFORMS=()\n' >>"$workflow_dir/platforms.env"
      ;;
  esac
  if run_preflight >"$test_root/config-$invalid.log" 2>&1; then
    fail "workflow accepted $invalid platform configuration"
  fi
done
cp "$test_root/workflow-config.env" "$workflow_dir/platforms.env"
printf 'OFFLINE_RELEASE_PLATFORMS=()\n' >>"$workflow_dir/platforms.env"
run_preflight >"$test_root/publication-disabled.log" 2>&1
matrix | jq -e 'length == 0' >/dev/null || fail 'disabled publication scheduled platform jobs'
grep -Fx 'should_run=false' "$GITHUB_OUTPUT" >/dev/null || fail 'disabled publication scheduled a release'
cp "$test_root/workflow-config.env" "$workflow_dir/platforms.env"

make_archive "$PLATFORM" true
cp "$test_root/$archive" "$TEST_RELEASE_ASSETS/$archive"
run_preflight
matrix | jq -e --argjson count "$release_platform_count" \
  'length == $count and .[0].build_archive == false' >/dev/null ||
  fail 'CI rejected the new validation tool profile'
for field in YQ_VERSION HELM_SCHEMA_PLUGIN_VERSION; do
  cp "$test_root/payload/$RELEASE_TAG/release.env" "$test_root/profile.env"
  sed -i "/^$field=/d" "$test_root/payload/$RELEASE_TAG/release.env"
  repack_archive
  cp "$test_root/$archive" "$TEST_RELEASE_ASSETS/$archive"
  if run_ci publish "$test_root/nonexistent-output" >"$test_root/missing-$field.log" 2>&1; then
    fail "publish accepted missing $field"
  fi
  cp "$test_root/profile.env" "$test_root/payload/$RELEASE_TAG/release.env"
done
repack_archive
cp "$test_root/$archive" "$TEST_RELEASE_ASSETS/$archive"
run_ci publish "$test_root/nonexistent-output"
find "$TEST_RELEASE_ASSETS" -maxdepth 1 -type f -delete
: >"$TEST_UPLOAD_LOG"
make_archive

TEST_RELEASE_ERROR=404 run_preflight >"$test_root/absent.log"
grep -Fx 'should_run=false' "$GITHUB_OUTPUT" >/dev/null || fail 'missing release was not skipped'
if TEST_RELEASE_ERROR=403 run_preflight >"$test_root/denied.log" 2>&1; then
  fail 'API permission failure was hidden'
fi
if INPUT_RELEASE_TAG=bad-tag run_preflight >"$test_root/tag.log" 2>&1; then
  fail 'invalid tag was accepted'
fi
if TEST_COMMIT=2222222222222222222222222222222222222222 run_preflight >"$test_root/commit.log" 2>&1; then
  fail 'tag/commit mismatch was accepted'
fi

cp "$test_root/$archive" "$TEST_RELEASE_ASSETS/$archive"
TEST_TAG_TYPE=tag run_preflight
matrix | jq -e --argjson count "$release_platform_count" \
  'length == $count and .[0].build_archive == false and all(.[1:][]; .build_archive == true)' >/dev/null ||
  fail 'missing checksum scheduled an archive rebuild'

run_ci publish "$test_root/nonexistent-output"
[[ $(<"$TEST_UPLOAD_LOG") == "$archive.sha256"$'\n'dotfiles-release$'\n'dotfiles-release.sha256 ]] ||
  fail 'checksum/script repair uploaded an existing archive'
cmp -s "$TEST_RELEASE_ASSETS/dotfiles-release" "$test_root/payload/$RELEASE_TAG/dotfiles-release" ||
  fail 'published manager differs from the release snapshot'
HOME="$test_root/empty-home" bash "$TEST_RELEASE_ASSETS/dotfiles-release" verify \
  "$TEST_RELEASE_ASSETS/$archive" >/dev/null ||
  fail 'published manager does not work outside the checkout'
(cd "$TEST_RELEASE_ASSETS" && sha256sum --check --strict "$archive.sha256" >/dev/null)
[[ -s $TEST_RELEASE_ASSETS/dotfiles-release.sha256 ]] || fail 'published standalone manager has no checksum'
(cd "$TEST_RELEASE_ASSETS" && sha256sum --check --strict dotfiles-release.sha256 >/dev/null)
for source in 'system.env (runtime and Docker)' 'tools.env (TOOL_CHECKS)' \
  scripts/setup-lib scripts/setup-system-lib scripts/setup-tools-lib \
  scripts/dotfiles-release-lib scripts/dotfiles-release; do
  if ! grep -Fx "##### BEGIN $source #####" "$TEST_RELEASE_ASSETS/dotfiles-release" >/dev/null ||
    ! grep -Fx "##### END $source #####" "$TEST_RELEASE_ASSETS/dotfiles-release" >/dev/null; then
    fail "published manager does not identify its $source source block"
  fi
done
grep -F 'fixture-release-package' "$TEST_RELEASE_ASSETS/dotfiles-release" >/dev/null ||
  fail 'standalone manager used the workflow OS configuration instead of the release snapshot'
run_preflight
matrix | jq -e --argjson count "$((release_platform_count - 1))" \
  'length == $count and all(.[]; .platform != "debian-13-x86_64")' >/dev/null ||
  fail 'complete platform was not skipped'
upload_before=$(sha256sum "$TEST_UPLOAD_LOG")
run_ci publish "$test_root/nonexistent-output"
[[ $(sha256sum "$TEST_UPLOAD_LOG") == "$upload_before" ]] || fail 'complete assets were uploaded twice'

printf '\nmodified manager\n' >>"$TEST_RELEASE_ASSETS/dotfiles-release"
if run_ci publish "$test_root/nonexistent-output" >"$test_root/bad-manager-publish.log" 2>&1; then
  fail 'publish replaced a mismatched manager'
fi
[[ $(sha256sum "$TEST_UPLOAD_LOG") == "$upload_before" ]] || fail 'manager mismatch changed release assets'
cp "$test_root/payload/$RELEASE_TAG/dotfiles-release" "$TEST_RELEASE_ASSETS/dotfiles-release"

printf 'invalid checksum\n' >"$TEST_RELEASE_ASSETS/dotfiles-release.sha256"
if run_ci publish "$test_root/nonexistent-output" >"$test_root/bad-manager-checksum-publish.log" 2>&1; then
  fail 'publish replaced a mismatched manager checksum'
fi
[[ $(sha256sum "$TEST_UPLOAD_LOG") == "$upload_before" ]] || fail 'manager checksum mismatch changed release assets'
(cd "$TEST_RELEASE_ASSETS" && sha256sum dotfiles-release >dotfiles-release.sha256)

printf 'invalid checksum\n' >"$TEST_RELEASE_ASSETS/$archive.sha256"
if run_ci publish "$test_root/nonexistent-output" >"$test_root/bad-publish.log" 2>&1; then
  fail 'publish replaced a mismatched sidecar'
fi
find "$TEST_RELEASE_ASSETS" -maxdepth 1 -type f -delete

make_archive amzn-2023-x86_64
cp "$test_root/$archive" "$TEST_RELEASE_ASSETS/$archive"
if run_ci publish "$test_root/nonexistent-output" >"$test_root/platform.log" 2>&1; then
  fail 'wrong-platform archive was accepted'
fi
grep -F 'archive platform or commit does not match the release job' "$test_root/platform.log" >/dev/null ||
  fail 'platform mismatch was not identified'

make_archive
ln -s "$test_root/outside" "$test_root/payload/$RELEASE_TAG/escape"
repack_archive
cp "$test_root/$archive" "$TEST_RELEASE_ASSETS/$archive"
if run_ci publish "$test_root/nonexistent-output" >"$test_root/escape.log" 2>&1; then
  fail 'absolute escaping symlink was accepted'
fi
[[ ! -e $test_root/outside ]] || fail 'unsafe archive wrote outside its root'
unlink "$test_root/payload/$RELEASE_TAG/escape"
tar -C "$test_root/payload" --transform="s|$RELEASE_TAG/payload|$RELEASE_TAG/../outside|" \
  -czf "$TEST_RELEASE_ASSETS/$archive" "$RELEASE_TAG"
if run_ci publish "$test_root/nonexistent-output" >"$test_root/traversal.log" 2>&1; then
  fail 'archive path traversal was accepted'
fi
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
[[ $(grep -Fxc "$archive" "$TEST_UPLOAD_LOG") -eq 1 &&
$(grep -Fxc "$archive.sha256" "$TEST_UPLOAD_LOG") -eq 1 &&
$(grep -Fxc dotfiles-release "$TEST_UPLOAD_LOG") -eq 1 &&
$(grep -Fxc dotfiles-release.sha256 "$TEST_UPLOAD_LOG") -eq 1 ]] ||
  fail 'partial upload retry did not publish each asset exactly once'

for platform in "${OFFLINE_RELEASE_PLATFORMS[@]:1}"; do
  make_archive "$platform"
  asset=$RELEASE_TAG-$platform.tar.gz
  cp "$test_root/$archive" "$TEST_RELEASE_ASSETS/$asset"
  (cd "$TEST_RELEASE_ASSETS" && sha256sum "$asset" >"$asset.sha256")
done
TEST_RELEASE_DOWNLOAD_FAIL=1 run_preflight
[[ $(matrix) == '[]' ]] || fail 'complete release scheduled redundant work'
grep -Fx 'should_run=false' "$GITHUB_OUTPUT" >/dev/null || fail 'complete release did not skip work'

rm "$TEST_RELEASE_ASSETS/dotfiles-release.sha256"
TEST_RELEASE_DOWNLOAD_FAIL=1 run_preflight
matrix | jq -e 'length == 1 and .[0].platform == "debian-13-x86_64" and .[0].build_archive == false' >/dev/null ||
  fail 'missing manager checksum scheduled redundant archive builds'
: >"$TEST_UPLOAD_LOG"
run_ci publish "$test_root/nonexistent-output"
[[ $(<"$TEST_UPLOAD_LOG") == dotfiles-release.sha256 ]] || fail 'manager checksum repair uploaded existing assets'
(cd "$TEST_RELEASE_ASSETS" && sha256sum --check --strict dotfiles-release.sha256 >/dev/null)
run_preflight
[[ $(matrix) == '[]' ]] || fail 'manager checksum repair left redundant work'

find "$TEST_RELEASE_ASSETS" -maxdepth 1 -name dotfiles-release -delete
TEST_RELEASE_DOWNLOAD_FAIL=1 run_preflight
matrix | jq -e 'length == 1 and .[0].platform == "debian-13-x86_64" and .[0].build_archive == false' >/dev/null ||
  fail 'missing standalone manager scheduled redundant archive builds'
: >"$TEST_UPLOAD_LOG"
run_ci publish "$test_root/nonexistent-output"
[[ $(<"$TEST_UPLOAD_LOG") == dotfiles-release ]] || fail 'manager repair uploaded existing package assets'
run_preflight
[[ $(matrix) == '[]' ]] || fail 'manager repair left redundant work'

make_archive
export TEST_BUILD_ARCHIVE=$test_root/$archive
run_ci build "$source_dir" "$test_root/output" >"$test_root/build.log"
grep -Fx "pull ${DOCKER_IMAGES[$PLATFORM]}" "$TEST_DOCKER_LOG" >/dev/null ||
  fail 'build used the workflow image pin instead of the release snapshot'
grep -F 'fixture offline health succeeded' "$RUNNER_TEMP/dotfiles-evidence/$PLATFORM/offline-verify.log" >/dev/null ||
  fail 'build did not perform ordinary-user offline qualification'
for file in build.log prepare-runtime.log release.env build-manifest.txt archive.sha256; do
  [[ -s $RUNNER_TEMP/dotfiles-evidence/$PLATFORM/$file ]] || fail 'build evidence was not preserved'
done

cp "$source_dir/platforms.env" "$test_root/source-config.env"
printf 'DEBIAN_13_IMAGE=%s\n' "${DOCKER_IMAGES[debian-13-x86_64]}" >"$source_dir/platforms.env"
: >"$TEST_DOCKER_LOG"
if run_ci verify "$source_dir" "$test_root/output" >"$test_root/legacy-image.log" 2>&1; then
  fail 'qualification accepted obsolete image variables in a release snapshot'
fi
grep -F 'release snapshot must define DOCKER_IMAGES' "$test_root/legacy-image.log" >/dev/null ||
  fail 'qualification did not explain the unsupported image configuration'
[[ ! -s $TEST_DOCKER_LOG ]] || fail 'qualification touched Docker with obsolete image variables'
printf 'declare -gA DOCKER_IMAGES=()\n' >"$source_dir/platforms.env"
: >"$TEST_DOCKER_LOG"
if run_ci verify "$source_dir" "$test_root/output" >"$test_root/missing-image.log" 2>&1; then
  fail 'qualification accepted a release snapshot without its Docker image'
fi
[[ ! -s $TEST_DOCKER_LOG ]] || fail 'qualification touched Docker with a missing release image'
cp "$test_root/source-config.env" "$source_dir/platforms.env"

mv "$source_dir/scripts/setup-system-lib" "$test_root/setup-system-lib"
: >"$TEST_DOCKER_LOG"
if run_ci verify "$source_dir" "$test_root/output" >"$test_root/missing-system-lib.log" 2>&1; then
  fail 'qualification accepted a release snapshot without its system library'
fi
[[ ! -s $TEST_DOCKER_LOG ]] || fail 'qualification touched Docker without its system library'
mv "$test_root/setup-system-lib" "$source_dir/scripts/setup-system-lib"

for stage in BUILD VERIFY PREPARE; do
  failure_runner=$test_root/runner-$stage
  mkdir -p "$failure_runner"
  : >"$TEST_DOCKER_LOG"
  set +e
  env "TEST_${stage}_FAIL=1" RUNNER_TEMP="$failure_runner" \
    bash "$workflow_dir/scripts/dotfiles-release-ci" build "$source_dir" "$test_root/output" \
    >"$test_root/failure-$stage.log" 2>&1
  failure_status=$?
  set -e
  case $stage in
    BUILD)
      expected=81
      failure_log=build.log
      ;;
    VERIFY)
      expected=82
      failure_log=offline-verify.log
      ;;
    PREPARE)
      expected=83
      failure_log=prepare-runtime.log
      ;;
  esac
  [[ $failure_status -eq $expected ]] || fail "build hid $stage failure"
  grep -F 'failure' "$failure_runner/dotfiles-evidence/$PLATFORM/$failure_log" >/dev/null ||
    fail "build did not retain $stage failure evidence"
  grep -F 'rm --force dotfiles-builder-fixture-1-debian-13-x86_64' "$TEST_DOCKER_LOG" >/dev/null ||
    fail 'failed build did not clean up its containers'
done

qualification_archives=$test_root/qualification-archives
qualification_tmp=$test_root/'local with spaces'
qualification_parallel=$test_root/qualification-parallel
mkdir -p "$qualification_archives" "$qualification_tmp" "$qualification_parallel"
for platform in "${OFFLINE_TEST_PLATFORMS[@]}"; do
  make_archive "$platform"
  cp "$test_root/$archive" "$qualification_archives/dotfiles-${COMMIT_SHA:0:12}-$platform.tar.gz"
done
: >"$TEST_DOCKER_LOG"
TMPDIR="$qualification_tmp" TEST_BUILD_ARCHIVES_DIR="$qualification_archives" TEST_PARALLEL_DIR="$qualification_parallel" \
  run_task_test >"$test_root/qualification.log" 2>&1
awk -v expected="$test_platform_count" '
  /^built / { builds++ }
  / verify / {
    if (builds != expected) {
      exit 1
    }
    verifications++
  }
  END {
    if (builds != expected || verifications != expected) {
      exit 1
    }
  }
' "$TEST_DOCKER_LOG" || fail 'qualification did not build every package before installing them'
qualification_root=$(sed -n 's/^Offline packages and logs: //p' "$test_root/qualification.log")
for platform in "${OFFLINE_TEST_PLATFORMS[@]}"; do
  [[ -s $qualification_root/output/$platform/dotfiles-${COMMIT_SHA:0:12}-$platform.tar.gz &&
    -x $qualification_root/output/$platform/dotfiles-release ]] || fail 'qualification did not retain its artifacts'
  (cd "$qualification_root/output/$platform" && sha256sum --check --strict dotfiles-release.sha256 >/dev/null)
  grep -F 'fixture offline health succeeded' \
    "$qualification_root/dotfiles-evidence/$platform/offline-verify.log" >/dev/null ||
    fail "qualification did not install and check $platform without networking"
  [[ $(grep -Fxc "### $platform" "$qualification_root/summary.md") -eq 1 ]] ||
    fail "parallel qualification lost or duplicated the summary for $platform"
done
load_config "$source_dir/platforms.env"
for platform in "${OFFLINE_TEST_PLATFORMS[@]}"; do
  image=${DOCKER_IMAGES[$platform]}
  [[ $(grep -Fxc "pull $image" "$TEST_DOCKER_LOG") -eq 1 ]] || fail 'qualification did not use the pinned platform image'
done

: >"$TEST_DOCKER_LOG"
qualification_parallel=$test_root/qualification-parallel-failure
mkdir -p "$qualification_parallel"
set +e
TMPDIR="$qualification_tmp" TEST_BUILD_FAIL=1 TEST_BUILD_ARCHIVES_DIR="$qualification_archives" TEST_PARALLEL_DIR="$qualification_parallel" \
  run_ci test "$source_dir" >"$test_root/qualification-failure.log" 2>&1
qualification_status=$?
set -e
[[ $qualification_status -eq 81 ]] || fail 'qualification hid a failed parallel build'
[[ $(grep -c ' build ' "$TEST_DOCKER_LOG") -eq $test_platform_count ]] ||
  fail 'qualification did not launch every parallel build'
if grep -q ' verify ' "$TEST_DOCKER_LOG"; then
  fail 'qualification installed packages when every build failed'
fi
for platform in "${OFFLINE_TEST_PLATFORMS[@]}"; do
  grep -E "^rm --force dotfiles-builder-local-.*-$platform " "$TEST_DOCKER_LOG" >/dev/null ||
    fail "failed parallel qualification did not clean up $platform"
done

for cpu_count in 4 2 1; do
  qualification_parallel=
  if ((cpu_count == 4)); then
    qualification_parallel=$test_root/qualification-parallel-partial
    mkdir -p "$qualification_parallel"
  fi
  worker_events=$test_root/qualification-workers-$cpu_count
  : >"$TEST_DOCKER_LOG"
  set +e
  TMPDIR="$qualification_tmp" TEST_BUILD_ARCHIVES_DIR="$qualification_archives" \
    TEST_CI_CPUS="$cpu_count" TEST_WORKER_EVENTS="$worker_events" \
    TEST_PARALLEL_DIR="$qualification_parallel" TEST_PARALLEL_VERIFY_COUNT=3 \
    TEST_BUILD_FAIL="$build_failure_platform" TEST_VERIFY_FAIL="$verify_failure_platform" \
    run_ci test "$source_dir" >"$test_root/qualification-partial.log" 2>&1
  qualification_status=$?
  set -e
  [[ $qualification_status -eq 81 ]] || fail 'qualification hid the failed platform'
  [[ $(grep -c ' build ' "$TEST_DOCKER_LOG") -eq $test_platform_count &&
    $(grep -c ' verify ' "$TEST_DOCKER_LOG") -eq $((test_platform_count - 1)) ]] ||
    fail 'one failed platform stopped qualification of the others'
  awk -v cpus="$cpu_count" -v builds="$test_platform_count" \
    -v verifications="$((test_platform_count - 1))" '
    $2 == "start" { active[$1]++; if (active[$1] > peak[$1]) peak[$1] = active[$1] }
    $2 == "end" { active[$1]--; completed[$1]++ }
    { if (active[$1] < 0 || active[$1] > cpus) failed = 1 }
    END {
      if (failed || active["build"] || active["verify"] ||
          completed["build"] != builds || completed["verify"] != verifications ||
          peak["build"] != (cpus < builds ? cpus : builds) ||
          peak["verify"] != (cpus < verifications ? cpus : verifications)) exit 1
    }
  ' "$worker_events" || fail "qualification did not respect $cpu_count available CPUs"
  qualification_root=$(sed -n 's/^Offline packages and logs: //p' "$test_root/qualification-partial.log")
  for platform in "${OFFLINE_TEST_PLATFORMS[@]}"; do
    if [[ $platform == "$build_failure_platform" ]]; then
      result='build=81 verify=skipped'
    elif [[ $platform == "$verify_failure_platform" ]]; then
      result='build=0 verify=82'
    else
      result='build=0 verify=0'
    fi
    grep -Fx "$platform: $result; logs: $qualification_root/dotfiles-evidence/$platform" \
      "$qualification_root/summary.md" >/dev/null || fail "qualification lost the final result for $platform"
    [[ -s $qualification_root/dotfiles-evidence/$platform/build-only.log ]] || fail "qualification lost the build log for $platform"
    if [[ $platform != "$build_failure_platform" ]]; then
      [[ -s $qualification_root/dotfiles-evidence/$platform/verify.log ]] || fail "qualification lost the verification log for $platform"
    fi
  done
  grep -F 'fixture build failure' \
    "$qualification_root/dotfiles-evidence/$build_failure_platform/build-only.log" >/dev/null ||
    fail 'qualification lost the failed build output'
  grep -F 'fixture offline failure' \
    "$qualification_root/dotfiles-evidence/$verify_failure_platform/verify.log" >/dev/null ||
    fail 'qualification lost the failed verification output'
  grep -F 'fixture offline health succeeded' \
    "$qualification_root/dotfiles-evidence/$successful_platform/verify.log" >/dev/null ||
    fail 'qualification did not finish a successful platform after other failures'
done

for alias in "${!PLATFORM_ALIASES[@]}"; do
  platform=${PLATFORM_ALIASES[$alias]}
  [[ " ${OFFLINE_TEST_PLATFORMS[*]} " == *" $platform "* ]] || continue
  : >"$TEST_DOCKER_LOG"
  TMPDIR="$qualification_tmp" TEST_BUILD_ARCHIVES_DIR="$qualification_archives" \
    run_task_test -- "$alias" >"$test_root/qualification-single.log" 2>&1
  [[ $(grep -c ' build ' "$TEST_DOCKER_LOG") -eq 1 && $(grep -c ' verify ' "$TEST_DOCKER_LOG") -eq 1 ]] ||
    fail 'single-platform qualification ran other platforms'
  grep -F "$platform: build=0 verify=0;" "$test_root/qualification-single.log" >/dev/null ||
    fail 'single-platform qualification did not finish the selected platform'
done

for phase in build verify; do
  ready=$test_root/cancellation-$phase.ready
  TMPDIR="$qualification_tmp" TEST_BUILD_ARCHIVES_DIR="$qualification_archives" \
    TEST_HANG_PHASE="$phase" TEST_WORKER_READY="$ready" \
    setsid env --default-signal=INT,QUIT bash "$workflow_dir/scripts/dotfiles-release-ci" \
    test "$source_dir" debian-13-x86_64 >"$test_root/cancellation-$phase.log" 2>&1 &
  cancellation_pid=$!
  deadline=$((SECONDS + 10))
  until [[ -s $ready ]]; do
    ((SECONDS < deadline)) || fail "qualification did not reach the blocked $phase worker"
    sleep 0.05
  done
  worker_pid=$(<"$ready")
  [[ $worker_pid =~ ^[1-9][0-9]*$ ]] || fail 'blocked worker did not report a PID'
  session=$(ps -o sid= -p "$cancellation_pid")
  [[ ${session//[[:space:]]/} == "$cancellation_pid" ]] || fail 'cancellation test did not create a private session'
  kill -TERM "$cancellation_pid"
  deadline=$((SECONDS + 10))
  while kill -0 "$cancellation_pid" 2>/dev/null; do
    ((SECONDS < deadline)) || fail "qualification cancellation left a blocked $phase worker"
    sleep 0.05
  done
  cancellation_status=0
  wait "$cancellation_pid" || cancellation_status=$?
  [[ $cancellation_status == 143 ]] || fail "qualification hid cancellation during $phase"
  if kill -0 "$worker_pid" 2>/dev/null; then
    fail "cancelled $phase worker is still running"
  fi
  cancellation_pid=
done

cat >>"$source_dir/platforms.env" <<'EOF'
PLATFORM_ALIASES[fixture]=ubuntu-24.04-x86_64
OFFLINE_TEST_PLATFORMS=(ubuntu-24.04-x86_64)
OFFLINE_RELEASE_PLATFORMS=()
EOF
git -C "$source_dir" add platforms.env
git -C "$source_dir" -c user.name=fixture -c user.email=fixture@example.invalid \
  commit -qm 'reduced qualification configuration'
TEST_COMMIT=$(git -C "$source_dir" rev-parse HEAD)
COMMIT_SHA=$TEST_COMMIT
RELEASE_TAG=dotfiles-${TEST_COMMIT:0:12}
archive=$RELEASE_TAG-$PLATFORM.tar.gz
make_archive ubuntu-24.04-x86_64
cp "$test_root/$archive" "$qualification_archives/dotfiles-${COMMIT_SHA:0:12}-ubuntu-24.04-x86_64.tar.gz"
for alias in '' fixture; do
  task_args=()
  [[ -z $alias ]] || task_args=(-- "$alias")
  : >"$TEST_DOCKER_LOG"
  TMPDIR="$qualification_tmp" TEST_BUILD_ARCHIVES_DIR="$qualification_archives" \
    run_task_test "${task_args[@]}" >"$test_root/configured-selection.log" 2>&1
  [[ $(grep -c ' build ' "$TEST_DOCKER_LOG") == 1 && $(grep -c ' verify ' "$TEST_DOCKER_LOG") == 1 ]] ||
    fail 'platforms.env did not restrict qualification to one platform'
  grep -F 'ubuntu-24.04-x86_64: build=0 verify=0;' "$test_root/configured-selection.log" >/dev/null ||
    fail 'platforms.env did not control the new alias and default test selection'
done
: >"$TEST_DOCKER_LOG"
if run_task_test -- debian13 >"$test_root/omitted-platform.log" 2>&1; then
  fail 'task test accepted a platform omitted from the test list'
fi
[[ ! -s $TEST_DOCKER_LOG ]] || fail 'an omitted qualification platform touched Docker'

: >"$TEST_DOCKER_LOG"
if run_task_test -- invalid-platform >"$test_root/qualification-alias.log" 2>&1; then
  fail 'task test accepted an unsupported alias'
fi
[[ ! -s $TEST_DOCKER_LOG ]] || fail 'task test started Docker for an unsupported alias'
: >"$TEST_DOCKER_LOG"
if run_ci test "$source_dir" invalid-platform >"$test_root/qualification-platform.log" 2>&1; then
  fail 'qualification accepted an unsupported platform'
fi
[[ ! -s $TEST_DOCKER_LOG ]] || fail 'qualification started Docker for an unsupported platform'

printf 'uncommitted\n' >"$source_dir/uncommitted"
: >"$TEST_DOCKER_LOG"
if run_ci test "$source_dir" >"$test_root/qualification-dirty.log" 2>&1; then
  fail 'qualification accepted an uncommitted checkout'
fi
[[ ! -s $TEST_DOCKER_LOG ]] || fail 'qualification started Docker for an uncommitted checkout'

printf 'dotfiles_release_ci: tests passed\n'
