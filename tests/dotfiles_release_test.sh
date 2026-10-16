#!/usr/bin/env bash

set -euo pipefail

test_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/dotfiles_release" && pwd)
scenarios=(profiles validation_tools paths publication recovery health lifecycle integrity locking)
if (($#)); then scenarios=("$@"); fi
for scenario in "${scenarios[@]}"; do
  case $scenario in
    profiles | validation_tools | paths | publication | recovery | health | lifecycle | integrity | locking) ;;
    *) printf 'Unknown scenario: %s\nAvailable: profiles validation_tools paths publication recovery health lifecycle integrity locking\n' "$scenario" >&2; exit 2 ;;
  esac
  printf 'Dotfiles release: %s\n' "$scenario"
  bash "$test_dir/${scenario}_test.sh"
done

printf 'Dotfiles release tests passed\n'
