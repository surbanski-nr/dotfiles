#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_bin=$(mktemp -d)

cleanup() {
  find "$test_bin" -depth -delete
}
trap cleanup EXIT

for command_name in bash dirname find git head jq mktemp sh sort timeout tmux yamllint; do
  command_path=$(command -v "$command_name")
  ln -s "$command_path" "$test_bin/$command_name"
done

if PATH="$test_bin" command -v rg >/dev/null 2>&1; then
  printf 'FAIL: isolated validation PATH unexpectedly contains rg\n' >&2
  exit 1
fi

PATH="$test_bin" /bin/bash "$repo_dir/scripts/validate" configs
printf 'Validation tests passed\n'
