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
relocated=$test_root/'relocated release with spaces'
package=$original/share/nvim2/mason/packages/debugpy
mkdir -p "$package/venv/bin" "$original/share/nvim2/mason/bin"
install -m 0755 "$repo_dir/tests/fixtures/scripts/debug-python" "$package/venv/bin/python"
for command_name in debugpy debugpy-adapter; do
  install -m 0755 "$repo_dir/scripts/offline-debug-adapter" "$package/$command_name"
  ln -s "../packages/debugpy/$command_name" "$original/share/nvim2/mason/bin/$command_name"
done
mv -T -- "$original" "$relocated"
package=$relocated/share/nvim2/mason/packages/debugpy

for command_name in debugpy debugpy-adapter; do
  module=debugpy
  [[ $command_name != debugpy-adapter ]] || module=debugpy.adapter
  output=$("$relocated/share/nvim2/mason/bin/$command_name" --version 'literal ; value' '')
  expected=$(printf 'python=%s\n<%s>\n<%s>\n<%s>\n<%s>\n<%s>\n<%s>\n<%s>\n<%s>\n<%s>\n' \
    "$package/venv/bin/python" -I -B -X frozen_modules=off -m "$module" --version 'literal ; value' '')
  [[ $output == "$expected" ]] || fail "$command_name lost its relocated venv, isolation flags or literal arguments: $output"
done

set +e
FIXTURE_PYTHON_EXIT_CODE=42 "$package/debugpy-adapter" --help >/dev/null
status=$?
set -e
[[ $status -eq 42 ]] || fail 'debug adapter launcher did not preserve the Python exit status'

install -m 0755 "$repo_dir/scripts/offline-debug-adapter" "$package/unknown-adapter"
set +e
output=$("$package/unknown-adapter" 2>&1)
status=$?
set -e
[[ $status -eq 1 && $output == *'unsupported launcher name: unknown-adapter'* ]] ||
  fail 'debug adapter launcher accepted an unsupported entry point'

printf 'Offline Python debug adapter launcher tests passed\n'
