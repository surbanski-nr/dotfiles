#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

python_repository=$test_root/python-repository
python_home=$test_root/python-home
python_xdg=$test_root/python-xdg
python_log=$test_root/python.log
make_test_repo "$python_repository"
cp "$test_repository/tools.env" "$python_repository/tools.env"
printf 'TOOL_RELEASES[python]=%q\n' \
  $'\n3.9.7|https://example.invalid/python-3.9.7.tar.gz|1111111111111111111111111111111111111111111111111111111111111111\n3.9.8|https://example.invalid/python-3.9.8.tar.gz|2222222222222222222222222222222222222222222222222222222222222222\n' \
  >>"$python_repository/tools.env"
printf 'python 3.10.0\nnodejs 20.0.0\n' >"$python_repository/.tool-versions"
printf '3.10.0\n' >"$python_repository/.python-version"
cp "$python_repository/.tool-versions" "$test_root/python-tool-versions-before"
cp "$python_repository/.python-version" "$test_root/python-version-before"
(
  cd "$python_repository"
  TEST_UV_LOG="$python_log" XDG_CONFIG_HOME="$python_xdg" \
    run_setup "$python_home" "$python_repository" "$archive_root" python
)
[[ -x $python_home/bin/uv && -d $python_home/.local/share/uv/python/3.9.7 &&
  -d $python_home/.local/share/uv/python/3.9.8 ]] ||
  fail 'Python setup did not install uv and all catalog versions'
[[ $(<"$python_xdg/uv/.python-version") == 3.9.7 ]] ||
  fail 'Python global pin did not select the first catalog record'
cmp "$python_repository/.tool-versions" "$test_root/python-tool-versions-before" ||
  fail 'Python setup changed project .tool-versions'
cmp "$python_repository/.python-version" "$test_root/python-version-before" ||
  fail 'Python setup changed project .python-version'
[[ ! -e $python_home/.asdf && ! -e $python_home/bin/python && ! -e $python_home/bin/python3 ]] ||
  fail 'Python setup introduced asdf or extra public interpreter links'
TEST_UV_LOG="$python_log" XDG_CONFIG_HOME="$python_xdg" \
  run_setup "$python_home" "$python_repository" "$test_root/no-downloads" python
[[ $(<"$python_xdg/uv/.python-version") == 3.9.7 ]] ||
  fail 'Python setup rerun changed the catalog default'
printf '3.9.0\n' >"$python_xdg/uv/.python-version"
if TEST_UV_LOG="$python_log" TEST_UV_FAIL_VERSION=3.9.8 XDG_CONFIG_HOME="$python_xdg" \
  run_setup "$python_home" "$python_repository" "$test_root/no-downloads" python \
  >"$test_root/python-install-failed.log" 2>&1; then
  fail 'Python setup hid a provider installation failure'
fi
[[ $(<"$python_xdg/uv/.python-version") == 3.9.0 ]] ||
  fail 'Python installation failure changed the global pin'

printf 'setup_tools: python passed\n'
