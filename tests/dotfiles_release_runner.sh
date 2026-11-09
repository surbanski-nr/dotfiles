#!/usr/bin/env bash

set -euo pipefail

test_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/dotfiles_release" && pwd)
available=(
  verification
  tool_lists
  selection
  mason
  validation_tools
  paths
  publication
  recovery
  health
  lifecycle
  integrity
  locking
  online
)
scenarios=("${available[@]}")
if (($#)); then
  scenarios=("$@")
fi
for scenario in "${scenarios[@]}"; do
  if [[ ! $scenario =~ ^[a-z_]+$ || ! -f $test_dir/${scenario}_test.sh ]]; then
    printf "Unknown scenario: %s\nAvailable: %s\n" "$scenario" "${available[*]}" >&2
    exit 2
  fi
  printf "dotfiles_release: running %s\n" "$scenario"
  bash "$test_dir/${scenario}_test.sh"
done

printf "dotfiles_release: all scenarios passed\n"
