#!/usr/bin/env bash

set -euo pipefail

test_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/setup_tools" && pwd)
scenarios=(install python configuration ownership archives recovery locking)
if (($#)); then scenarios=("$@"); fi
for scenario in "${scenarios[@]}"; do
  case $scenario in
    install | python | configuration | ownership | archives | recovery | locking) ;;
    *) printf 'Unknown scenario: %s\nAvailable: install python configuration ownership archives recovery locking\n' "$scenario" >&2; exit 2 ;;
  esac
  printf 'Setup tools: %s\n' "$scenario"
  bash "$test_dir/${scenario}_test.sh"
done

printf 'Setup tools tests passed\n'
