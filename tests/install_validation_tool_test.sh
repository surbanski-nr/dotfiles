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
    bash "$test_repo/scripts/install-validation-tool" "$1" 2>&1)
  status=$?
  set -e
}

mkdir -p "$test_repo/scripts" "$test_bin" "$tools_dir"
mkdir -p "$test_repo/nvim2/.config/nvim2/python-locks"
cp "$repo_dir/scripts/install-validation-tool" "$test_repo/scripts/"
cp "$repo_dir/scripts/setup-lib" "$test_repo/scripts/"
cp "$repo_dir/tools.env" "$test_repo/tools.env"
cp "$repo_dir/validation.env" "$test_repo/validation.env"
ln -s "$repo_dir/tests/fixtures/scripts/curl-copy" "$test_bin/curl"

printf 'VALIDATION_TOOLS+=(missing-validation-tool)\n' >>"$test_repo/validation.env"
run_installer task
[[ $status -ne 0 && $output == *'has no releases for validation tool missing-validation-tool'* ]] ||
  fail 'validation profile accepted a missing native tool'
cp "$repo_dir/validation.env" "$test_repo/validation.env"

cat >>"$test_repo/validation.env" <<'EOF'
VALIDATION_RELEASES[yamllint]=${VALIDATION_RELEASES[stylua]}
EOF
run_installer yamllint
[[ $status -ne 0 && $output == *'yamllint version belongs in YAMLLINT_VERSION'* ]] ||
  fail 'validation profile accepted a native yamllint release'
cp "$repo_dir/validation.env" "$test_repo/validation.env"

cat >"$tools_dir/actionlint" <<'EOF'
#!/usr/bin/env bash
printf '1.0.0\n'
EOF
chmod +x "$tools_dir/actionlint"
old_actionlint_hash=$(sha256sum "$tools_dir/actionlint")

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
cat >>"$test_repo/validation.env" <<EOF
VALIDATION_RELEASES[actionlint]='
2.0.0|https://example.invalid/actionlint.tar.gz|$candidate_hash
'
EOF

TEST_DOWNLOAD_FILE=$candidate_archive
TEST_DOWNLOAD_FAIL=1
export TEST_DOWNLOAD_FILE TEST_DOWNLOAD_FAIL
run_installer actionlint
[[ $status -ne 0 ]] || fail 'installer accepted a failed download'
[[ $(sha256sum "$tools_dir/actionlint") == "$old_actionlint_hash" ]] ||
  fail 'failed download replaced the existing actionlint'
[[ $("$tools_dir/actionlint" -version) == 1.0.0 ]] ||
  fail 'actionlint stopped working after a failed download'

TEST_DOWNLOAD_FAIL=0
export TEST_DOWNLOAD_FAIL
bad_archive=$test_root/not-a-tar.gz
printf 'not an archive\n' >"$bad_archive"
bad_hash=$(sha256sum "$bad_archive")
bad_hash=${bad_hash%% *}
cp "$repo_dir/validation.env" "$test_repo/validation.env"
cat >>"$test_repo/validation.env" <<EOF
VALIDATION_RELEASES[actionlint]='
2.0.0|https://example.invalid/actionlint.tar.gz|$bad_hash
'
EOF
TEST_DOWNLOAD_FILE=$bad_archive
export TEST_DOWNLOAD_FILE
run_installer actionlint
[[ $status -ne 0 ]] || fail 'installer accepted a failed archive extraction'
[[ $(sha256sum "$tools_dir/actionlint") == "$old_actionlint_hash" ]] ||
  fail 'failed extraction replaced the existing actionlint'

cp "$repo_dir/validation.env" "$test_repo/validation.env"
cat >>"$test_repo/validation.env" <<EOF
VALIDATION_RELEASES[actionlint]='
2.0.0|https://example.invalid/actionlint.tar.gz|$candidate_hash
'
EOF
TEST_DOWNLOAD_FILE=$candidate_archive
export TEST_DOWNLOAD_FILE
run_installer actionlint
[[ $status -ne 0 ]] || fail 'installer accepted an invalid candidate executable'
[[ $output == *'candidate validation failed'* ]] ||
  fail 'installer did not identify candidate validation failure'
[[ $(sha256sum "$tools_dir/actionlint") == "$old_actionlint_hash" ]] ||
  fail 'invalid candidate replaced the existing actionlint'

python_candidate=$test_root/python-candidate/python/bin
python_archive=$test_root/python.tar.gz
mkdir -p "$python_candidate"
cp "$repo_dir/tests/fixtures/scripts/python3-venv" "$python_candidate/python3"
tar -czf "$python_archive" -C "$test_root/python-candidate" python
python_hash=$(sha256sum "$python_archive")
python_hash=${python_hash%% *}
cat >>"$test_repo/validation.env" <<EOF
VALIDATION_RELEASES[python]='
3.12.12|https://example.invalid/python.tar.gz|$python_hash
'
EOF
TEST_DOWNLOAD_FILE=$python_archive
export TEST_DOWNLOAD_FILE
ln -s /bin/false "$test_bin/python3"

cat >"$tools_dir/yamllint" <<'EOF'
#!/usr/bin/env bash
printf 'yamllint 1.0.0\n'
EOF
chmod +x "$tools_dir/yamllint"
old_yamllint_hash=$(sha256sum "$tools_dir/yamllint")
printf 'YAMLLINT_VERSION=2.0.0\n' >>"$test_repo/validation.env"
printf 'yamllint==8.0.0\n' \
  >"$test_repo/nvim2/.config/nvim2/python-locks/yamllint.in"
printf 'yamllint==8.0.0 --hash=sha256:%064d\n' 0 \
  >"$test_repo/nvim2/.config/nvim2/python-locks/yamllint.lock"
TEST_VENV_PIP_FAIL=1
export TEST_VENV_PIP_FAIL
run_installer yamllint
[[ $status -ne 0 ]] || fail 'installer accepted a failed Yamllint pip install'
[[ $(sha256sum "$tools_dir/yamllint") == "$old_yamllint_hash" ]] ||
  fail 'failed pip install replaced the existing Yamllint'
[[ $("$tools_dir/yamllint" --version) == 'yamllint 1.0.0' ]] ||
  fail 'Yamllint stopped working after a failed pip install'
private_python=$(readlink -f "$tools_dir/python/bin/python3")
[[ $("$private_python" --version) == 'Python 3.12.12' ]] ||
  fail 'Yamllint did not bootstrap its pinned private Python without OS Python'
[[ ! -e $tools_dir/python3 ]] || fail 'validation added a public Python shim'

TEST_VENV_PIP_FAIL=0
export TEST_VENV_PIP_FAIL
run_installer yamllint
[[ $status -eq 0 ]] || fail "valid Yamllint activation failed: $output"
[[ -L $tools_dir/yamllint ]] || fail 'Yamllint activation did not publish a link'
[[ $("$tools_dir/yamllint" --version) == 'yamllint 2.0.0' ]] ||
  fail 'activated Yamllint did not use the validation pin independently of the editor pin'
yaml_executable=$(readlink -f "$tools_dir/yamllint")
[[ $(readlink -f "${yaml_executable%/*}/python") == "$private_python" ]] ||
  fail 'Yamllint venv still depends on the OS Python'

(
  exec 9>"$tools_dir/.install-python.lock"
  flock 9
  run_installer python
  [[ $status -ne 0 && $output == *'another validation Python installation is running'* &&
    $(readlink -f "$tools_dir/python/bin/python3") == "$private_python" ]] ||
    fail 'concurrent private Python setup ignored its lock or changed the active runtime'
)

TEST_DOWNLOAD_FAIL=1
TEST_VENV_PIP_FAIL=1
export TEST_DOWNLOAD_FAIL TEST_VENV_PIP_FAIL
run_installer yamllint
[[ $status -eq 0 && $(readlink -f "$tools_dir/yamllint") == "$yaml_executable" ]] ||
  fail 'matching private Python and Yamllint were not reused without network access'
TEST_DOWNLOAD_FAIL=0
export TEST_DOWNLOAD_FAIL
cat >>"$test_repo/validation.env" <<EOF
VALIDATION_RELEASES[python]='
3.12.13|https://example.invalid/python.tar.gz|$python_hash
'
EOF
run_installer yamllint
[[ $status -ne 0 && $output == *'python 3.12.13 candidate validation failed'* &&
  $(readlink -f "$tools_dir/python/bin/python3") == "$private_python" &&
  $(readlink -f "$tools_dir/yamllint") == "$yaml_executable" ]] ||
  fail 'invalid private Python replaced the working validation environment'

sed 's/Python 3.12.12/Python 3.12.13/' "$repo_dir/tests/fixtures/scripts/python3-venv" \
  >"$python_candidate/python3"
tar -czf "$python_archive" -C "$test_root/python-candidate" python
python_hash=$(sha256sum "$python_archive")
python_hash=${python_hash%% *}
cat >>"$test_repo/validation.env" <<EOF
VALIDATION_RELEASES[python]='
3.12.13|https://example.invalid/python.tar.gz|$python_hash
'
EOF
run_installer yamllint
[[ $status -ne 0 && $("$tools_dir/python/bin/python3" --version) == 'Python 3.12.13' &&
  $(readlink -f "$tools_dir/yamllint") == "$yaml_executable" && -x $private_python ]] ||
  fail 'failed Yamllint upgrade removed the previous venv or its Python'
TEST_VENV_PIP_FAIL=0
export TEST_VENV_PIP_FAIL
run_installer yamllint
[[ $status -eq 0 && $(readlink -f "$tools_dir/yamllint") != "$yaml_executable" ]] ||
  fail 'unchanged Yamllint pin did not rebuild its venv for a new Python'
yaml_executable=$(readlink -f "$tools_dir/yamllint")
[[ $(readlink -f "${yaml_executable%/*}/python") == $(readlink -f "$tools_dir/python/bin/python3") &&
  -x $private_python ]] || fail 'Yamllint upgrade did not retain independent versioned Python runtimes'

task_version=9.8.7
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
cp "$repo_dir/validation.env" "$test_repo/validation.env"
cat >>"$test_repo/validation.env" <<EOF
VALIDATION_RELEASES[task]='
$task_version|https://example.invalid/task.tar.gz|$task_hash
'
EOF
cat >>"$test_repo/tools.env" <<EOF
TOOL_RELEASES[task]='
9.8.6|https://example.invalid/development-task.tar.gz|$task_hash
'
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
[[ $status -eq 0 ]] || fail "validation Task pin was not installed independently of the development pin: $output"
[[ -x $tools_dir/task ]] || fail 'matching external Task was reused instead of installing privately'
[[ $("$tools_dir/task" --version) == "Task version: v$task_version" ]] ||
  fail 'privately installed Task does not run'

default_output=$(
  cd "$test_root"
  env -u VALIDATION_TOOLS_DIR PATH="$test_bin:$PATH" \
    bash "$test_repo/scripts/install-validation-tool" task 2>&1
) || fail "default validation Task installation failed: $default_output"
[[ -x $test_repo/bin/task ]] || fail 'default installation did not provide repository-local bin/task'
[[ $("$test_repo/bin/task" --version) == "Task version: v$task_version" ]] ||
  fail 'default repository-local Task does not run'
[[ ! -e $test_repo/.bin ]] || fail 'default installation created the old hidden tools directory'

cat >"$test_bin/task" <<'EOF'
#!/usr/bin/env bash
printf 'Task version: v0.0.0\n'
EOF
chmod +x "$test_bin/task"
TEST_DOWNLOAD_FAIL=1
export TEST_DOWNLOAD_FAIL
run_installer task
[[ $status -eq 0 ]] || fail "valid private Task was not reused: $output"
[[ $("$tools_dir/task" --version) == "Task version: v$task_version" ]] ||
  fail 'external Task replaced the valid private Task'

printf 'Validation tool installer tests passed\n'
