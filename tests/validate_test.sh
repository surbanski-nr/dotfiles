#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
test_bin=$test_root/bin

cleanup() {
  find "$test_root" -depth -delete
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p "$test_bin"
for command_name in bash cp dirname find git head jq mkdir mkfifo mktemp script sh sleep sort timeout tmux yamllint; do
  command_path=$(command -v "$command_name")
  ln -s "$command_path" "$test_bin/$command_name"
done

if PATH="$test_bin" command -v rg >/dev/null 2>&1; then
  fail 'isolated validation PATH unexpectedly contains rg'
fi

PATH="$test_bin" /bin/bash "$repo_dir/scripts/validate" configs

syntax_repo=$test_root/syntax-repo
mkdir -p "$syntax_repo/bash" "$syntax_repo/scripts" "$syntax_repo/tests"
cp "$repo_dir/scripts/validate" "$syntax_repo/scripts/validate"
cp "$repo_dir/bash/.bashrc" "$syntax_repo/bash/.bashrc"
cp "$repo_dir/bash/.bash_profile" "$syntax_repo/bash/.bash_profile"
cp "$repo_dir/bash/.bash_aliases" "$syntax_repo/bash/.bash_aliases"
cp "$repo_dir/tests/bash_test.sh" "$syntax_repo/tests/bash_test.sh"
cp "$repo_dir/release.env" "$syntax_repo/release.env"
cp "$repo_dir/validation.env" "$syntax_repo/validation.env"
cp "$repo_dir/versions.env" "$syntax_repo/versions.env"
cp "$repo_dir/system.env" "$syntax_repo/system.env"
cp "$repo_dir/probes.env" "$syntax_repo/probes.env"
cp "$repo_dir/README.md" "$syntax_repo/README.md"
printf 'if then\n' >"$syntax_repo/bash/.bash_profile"
ln -s "$(command -v shellcheck)" "$test_bin/shellcheck"

set +e
syntax_output=$(
  PATH="$test_bin" VALIDATION_TOOLS_DIR="$repo_dir/.cache/validation-tools" \
    /bin/bash "$syntax_repo/scripts/validate" bash 2>&1
)
syntax_status=$?
set -e
[[ $syntax_status -ne 0 ]] || fail 'Bash syntax gate accepted an invalid later file'
[[ $syntax_output == *'bash/.bash_profile'* ]] ||
  fail 'Bash syntax failure did not identify the invalid later file'

cp "$repo_dir/bash/.bash_profile" "$syntax_repo/bash/.bash_profile"
cat >"$syntax_repo/SETUP.md" <<'EOF'
```bash
if then
```
EOF
set +e
syntax_output=$(
  PATH="$test_bin" VALIDATION_TOOLS_DIR="$repo_dir/.cache/validation-tools" \
    /bin/bash "$syntax_repo/scripts/validate" bash 2>&1
)
syntax_status=$?
set -e
[[ $syntax_status -ne 0 ]] || fail 'documentation gate accepted invalid Bash syntax'
[[ $syntax_output == *'SETUP.md block starting at line 2'* ]] ||
  fail 'documentation syntax failure did not identify its source block'

real_tmux=$(command -v tmux)
rm "$test_bin/tmux"
ln -s "$repo_dir/tests/fixtures/validation/tmux-fail-show-options" \
  "$test_bin/tmux"
tmux_log=$test_root/tmux.log

set +e
PATH="$test_bin" TEST_REAL_TMUX="$real_tmux" TEST_TMUX_LOG="$tmux_log" \
  /bin/bash "$repo_dir/scripts/validate" configs >/dev/null 2>&1
tmux_status=$?
set -e
[[ $tmux_status -eq 73 ]] || fail 'tmux failure fixture returned an unexpected status'
IFS=$'\t' read -r tmux_home tmux_socket <"$tmux_log"
[[ -n $tmux_home && ! -e $tmux_home ]] ||
  fail 'tmux validation left its temporary HOME after failure'
[[ -n $tmux_socket ]] || fail 'tmux failure fixture did not record a socket'
if "$real_tmux" -L "$tmux_socket" has-session >/dev/null 2>&1; then
  fail 'tmux validation left its private server running after failure'
fi

ln -s "$(command -v actionlint)" "$test_bin/actionlint"
ln -s "$repo_dir/tests/fixtures/validation/zizmor-offline" "$test_bin/zizmor"
zizmor_log=$test_root/zizmor.log
env -u GH_TOKEN -u GITHUB_TOKEN TEST_ZIZMOR_LOG="$zizmor_log" \
  VALIDATION_TOOLS_DIR="$test_root/empty-tools" PATH="$test_bin" \
  /bin/bash "$repo_dir/scripts/validate" workflows
grep -Fx -- '--offline --persona=pedantic --config zizmor.yml .' "$zizmor_log" \
  >/dev/null || fail 'workflow validation did not select the offline Zizmor audit'

printf 'Validation tests passed\n'
