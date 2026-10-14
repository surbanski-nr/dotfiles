#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'find "$test_root" -depth -delete' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

original=$test_root/original
release=$test_root/'relocated release with spaces'
test_home=$test_root/home
mkdir -p "$original/bin" "$original/tools/go/bin" "$test_home/bin"
: >"$original/installed.sha256"
: >"$original/tools/go/bin/go"
chmod 0755 "$original/tools/go/bin/go"
for tool in nvim tmux; do
  mkdir -p "$original/tools/$tool/bin"
  install -m 0755 "$repo_dir/scripts/offline-$tool" "$original/bin/$tool"
  install -m 0755 "$repo_dir/tests/fixtures/scripts/launcher-tool" "$original/tools/$tool/bin/$tool"
  ln -s "../../current/bin/$tool" "$test_home/bin/$tool"
done
mv -T -- "$original" "$release"
ln -s "$release" "$test_root/current"

output=$(env -u NVIM_APPNAME HOME="$test_home" XDG_CONFIG_HOME=/user/config \
  XDG_DATA_HOME=/user/data GOROOT=/project/sdk GOTOOLCHAIN=auto \
  "$test_home/bin/nvim" -- 'literal ; value' '')
[[ $output == *"tool=$release/tools/nvim/bin/nvim"* && $output == *'app=nvim2'* &&
  $output == *"config=$release/config"* && $output == *"data=$release/share"* &&
  $output == *$'GOROOT=unset\nGOTOOLCHAIN=local'* &&
  $output == *$'<-->\n<literal ; value>\n<>' ]] ||
  fail "Nvim lost its release, isolated environment or literal arguments: $output"

output=$(HOME="$test_home" NVIM_APPNAME=personal XDG_CONFIG_HOME=/user/config \
  XDG_DATA_HOME=/user/data "$test_home/bin/nvim" file)
[[ $output == *'app=personal'* && $output == *$'config=/user/config\ndata=/user/data'* ]] ||
  fail 'Nvim changed the environment for a separate user profile'

output=$(HOME="$test_home" NVIM_APPNAME=nvim2 XDG_CONFIG_HOME=/user/config \
  XDG_DATA_HOME=/user/data GOROOT=/project/sdk GOTOOLCHAIN=auto \
  TERM=xterm-256color TEST_REPO_DIR="$repo_dir" TEST_SCENARIO=launcher-environment \
  "$test_home/bin/nvim" fixture-shell 2>"$test_root/shell.log")
[[ $output == *'xdg-config=/user/config xdg-data=/user/data'* &&
  $output == *'go-root=/project/sdk go-toolchain=auto'* ]] ||
  fail 'a shell started from Nvim did not recover the user environment'

config=$release/dotfiles/tmux/.tmux.conf
output=$("$test_home/bin/tmux" new-session 'literal ; value' '')
[[ $output == *"tool=$release/tools/tmux/bin/tmux"* && $output == *"tmux-config=$config"* &&
  $output == *"$(printf '<-f>\n<%s>\n<new-session>\n<literal ; value>\n<>' "$config")" ]] ||
  fail "tmux lost its release configuration or literal arguments: $output"
output=$("$test_home/bin/tmux" -f '/user/config with spaces' new-session)
[[ $output == *$'<-f>\n</user/config with spaces>\n<new-session>' &&
  $output != *"<$config>"* ]] || fail 'tmux replaced an explicit configuration'

for tool in nvim tmux; do
  if FIXTURE_LAUNCHER_EXIT_CODE=42 "$test_home/bin/$tool" --version >/dev/null; then
    fail "$tool hid the child exit status"
  else
    [[ $? -eq 42 ]] || fail "$tool changed the child exit status"
  fi
done

printf 'Offline Nvim and tmux launcher tests passed\n'
