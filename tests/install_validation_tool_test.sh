#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
test_repo=$test_root/repo
test_bin=$test_root/bin
tools_dir=$test_root/tools

cleanup() {
  find "$test_root" -depth -delete
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

run_installer() {
  set +e
  output=$(PATH="$test_bin:$PATH" VALIDATION_TOOLS_DIR="$tools_dir" \
    TEST_DOWNLOAD_FILE="${TEST_DOWNLOAD_FILE:-}" \
    TEST_DOWNLOAD_FAIL="${TEST_DOWNLOAD_FAIL:-0}" \
    TEST_VENV_PIP_FAIL="${TEST_VENV_PIP_FAIL:-0}" \
    TEST_YAMLLINT_VERSION="${TEST_YAMLLINT_VERSION:-}" \
    bash "$test_repo/scripts/install-validation-tool" "$1" 2>&1)
  status=$?
  set -e
}

mkdir -p "$test_repo/scripts" "$test_bin" "$tools_dir/bin"
cp "$repo_dir/scripts/install-validation-tool" "$test_repo/scripts/"
ln -s "$repo_dir/tests/fixtures/scripts/curl-copy" "$test_bin/curl"

cat >"$tools_dir/bin/actionlint" <<'EOF'
#!/usr/bin/env bash
printf '1.0.0\n'
EOF
chmod +x "$tools_dir/bin/actionlint"
old_actionlint_hash=$(sha256sum "$tools_dir/bin/actionlint")

candidate_dir=$test_root/actionlint-candidate
mkdir "$candidate_dir"
cat >"$candidate_dir/actionlint" <<'EOF'
#!/usr/bin/env bash
printf 'wrong-version\n'
EOF
chmod +x "$candidate_dir/actionlint"
candidate_archive=$test_root/actionlint.tar.gz
tar -czf "$candidate_archive" -C "$candidate_dir" actionlint
candidate_hash=$(sha256sum "$candidate_archive")
candidate_hash=${candidate_hash%% *}
cat >"$test_repo/validation.env" <<EOF
ACTIONLINT_VERSION=2.0.0
ACTIONLINT_SHA256=$candidate_hash
EOF

TEST_DOWNLOAD_FILE=$candidate_archive
TEST_DOWNLOAD_FAIL=1
export TEST_DOWNLOAD_FILE TEST_DOWNLOAD_FAIL
run_installer actionlint
[[ $status -ne 0 ]] || fail 'installer accepted a failed download'
[[ $(sha256sum "$tools_dir/bin/actionlint") == "$old_actionlint_hash" ]] ||
  fail 'failed download replaced the existing actionlint'
[[ $("$tools_dir/bin/actionlint" -version) == 1.0.0 ]] ||
  fail 'actionlint stopped working after a failed download'

TEST_DOWNLOAD_FAIL=0
export TEST_DOWNLOAD_FAIL
bad_archive=$test_root/not-a-tar.gz
printf 'not an archive\n' >"$bad_archive"
bad_hash=$(sha256sum "$bad_archive")
bad_hash=${bad_hash%% *}
cat >"$test_repo/validation.env" <<EOF
ACTIONLINT_VERSION=2.0.0
ACTIONLINT_SHA256=$bad_hash
EOF
TEST_DOWNLOAD_FILE=$bad_archive
export TEST_DOWNLOAD_FILE
run_installer actionlint
[[ $status -ne 0 ]] || fail 'installer accepted a failed archive extraction'
[[ $(sha256sum "$tools_dir/bin/actionlint") == "$old_actionlint_hash" ]] ||
  fail 'failed extraction replaced the existing actionlint'

cat >"$test_repo/validation.env" <<EOF
ACTIONLINT_VERSION=2.0.0
ACTIONLINT_SHA256=$candidate_hash
EOF
TEST_DOWNLOAD_FILE=$candidate_archive
export TEST_DOWNLOAD_FILE
run_installer actionlint
[[ $status -ne 0 ]] || fail 'installer accepted an invalid candidate executable'
[[ $output == *'candidate validation failed'* ]] ||
  fail 'installer did not identify candidate validation failure'
[[ $(sha256sum "$tools_dir/bin/actionlint") == "$old_actionlint_hash" ]] ||
  fail 'invalid candidate replaced the existing actionlint'

cat >"$tools_dir/bin/yamllint" <<'EOF'
#!/usr/bin/env bash
printf 'yamllint 1.0.0\n'
EOF
chmod +x "$tools_dir/bin/yamllint"
old_yamllint_hash=$(sha256sum "$tools_dir/bin/yamllint")
cat >"$test_repo/validation.env" <<'EOF'
YAMLLINT_VERSION=2.0.0
YAMLLINT_PATHSPEC_VERSION=0.12.1
YAMLLINT_PYYAML_VERSION=6.0.2
EOF
ln -s "$repo_dir/tests/fixtures/scripts/python3-venv" "$test_bin/python3"
TEST_VENV_PIP_FAIL=1
TEST_YAMLLINT_VERSION=2.0.0
export TEST_VENV_PIP_FAIL TEST_YAMLLINT_VERSION
run_installer yamllint
[[ $status -ne 0 ]] || fail 'installer accepted a failed Yamllint pip install'
[[ $(sha256sum "$tools_dir/bin/yamllint") == "$old_yamllint_hash" ]] ||
  fail 'failed pip install replaced the existing Yamllint'
[[ $("$tools_dir/bin/yamllint" --version) == 'yamllint 1.0.0' ]] ||
  fail 'Yamllint stopped working after a failed pip install'

TEST_VENV_PIP_FAIL=0
export TEST_VENV_PIP_FAIL
run_installer yamllint
[[ $status -eq 0 ]] || fail "valid Yamllint activation failed: $output"
[[ -L $tools_dir/bin/yamllint ]] || fail 'Yamllint activation did not publish a link'
[[ $("$tools_dir/bin/yamllint" --version) == 'yamllint 2.0.0' ]] ||
  fail 'activated Yamllint does not run from its final environment'

task_version=3.53.1
task_candidate_dir=$test_root/task-candidate
mkdir "$task_candidate_dir"
cat >"$task_candidate_dir/task" <<EOF
#!/usr/bin/env bash
printf 'Task version: v$task_version\\n'
EOF
chmod +x "$task_candidate_dir/task"
task_archive=$test_root/task.tar.gz
tar -czf "$task_archive" -C "$task_candidate_dir" task
task_hash=$(sha256sum "$task_archive")
task_hash=${task_hash%% *}
cat >"$test_repo/validation.env" <<EOF
TASK_VERSION=$task_version
TASK_SHA256=$task_hash
EOF
cat >"$test_bin/task" <<EOF
#!/usr/bin/env bash
printf 'Task version: v$task_version\\n'
EOF
chmod +x "$test_bin/task"

TEST_DOWNLOAD_FILE=$task_archive
TEST_DOWNLOAD_FAIL=0
export TEST_DOWNLOAD_FILE TEST_DOWNLOAD_FAIL
run_installer task
[[ $status -eq 0 ]] || fail "matching external Task blocked private installation: $output"
[[ -x $tools_dir/bin/task ]] || fail 'matching external Task was reused instead of installing privately'
[[ $("$tools_dir/bin/task" --version) == "Task version: v$task_version" ]] ||
  fail 'privately installed Task does not run'

cat >"$test_bin/task" <<'EOF'
#!/usr/bin/env bash
printf 'Task version: v0.0.0\n'
EOF
chmod +x "$test_bin/task"
TEST_DOWNLOAD_FAIL=1
export TEST_DOWNLOAD_FAIL
run_installer task
[[ $status -eq 0 ]] || fail "valid private Task was not reused: $output"
[[ $("$tools_dir/bin/task" --version) == "Task version: v$task_version" ]] ||
  fail 'external Task replaced the valid private Task'

printf 'Validation tool installer tests passed\n'
