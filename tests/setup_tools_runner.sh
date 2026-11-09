#!/usr/bin/env bash

set -euo pipefail

test_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/setup_tools" && pwd)
available=(
  install
  python
  configuration
  ownership
  archives
  recovery
  locking
  plugins
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
  printf "setup_tools: running %s\n" "$scenario"
  bash "$test_dir/${scenario}_test.sh"
done

printf "setup_tools: all scenarios passed\n"
