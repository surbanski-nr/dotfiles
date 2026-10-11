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
relocated=$test_root/'relocated Go release with spaces'
mkdir -p "$original/bin" "$original/tools/go/bin"
install -m 0755 "$repo_dir/scripts/offline-go" "$original/bin/go"
install -m 0755 "$repo_dir/tests/fixtures/scripts/go" "$original/tools/go/bin/go"
mv -T -- "$original" "$relocated"

output=$(GOROOT=/other/sdk GOTOOLCHAIN=auto GOPATH=/project/modules \
  "$relocated/bin/go" version 'literal ; value' '')
[[ $output == *"go=$relocated/tools/go/bin/go"* && $output == *'GOROOT=unset'* &&
  $output == *'GOTOOLCHAIN=local'* && $output == *'GOPATH=/project/modules'* &&
  $output == *$'<version>\n<literal ; value>\n<>' ]] ||
  fail "Go launcher lost its relocated SDK, environment or arguments: $output"

for was_set in 0 1; do
  original_config=$test_root/user-config
  launcher_config=$original_config
  [[ $was_set != 0 ]] || original_config=$test_root/home/.config
  [[ $was_set != 0 ]] || launcher_config=''
  output=$(HOME="$test_root/home" XDG_CONFIG_HOME="$relocated/config" \
    DOTFILES_LAUNCHER_XDG_CONFIG_HOME_SET=$was_set \
    DOTFILES_LAUNCHER_XDG_CONFIG_HOME=$launcher_config \
    "$relocated/bin/go" env)
  [[ $output == *"XDG_CONFIG_HOME=$original_config"* ]] ||
    fail "Go launcher kept Neovim's immutable configuration: $output"
done

set +e
FIXTURE_GO_EXIT_CODE=42 "$relocated/bin/go" version >/dev/null
status=$?
set -e
[[ $status -eq 42 ]] || fail 'Go launcher did not preserve the SDK exit status'

printf 'Offline Go SDK launcher tests passed\n'
