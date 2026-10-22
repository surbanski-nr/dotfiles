#!/usr/bin/env bash

set -euo pipefail

test_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/dotfiles_release" && pwd)
scenarios=(verification profiles validation_tools paths publication recovery health lifecycle integrity locking)
if (($#)); then scenarios=("$@"); fi
for scenario in "${scenarios[@]}"; do
  case $scenario in
    verification | profiles | validation_tools | paths | publication | recovery | health | lifecycle | integrity | locking) ;;
    *) printf 'Unknown scenario: %s\nAvailable: verification profiles validation_tools paths publication recovery health lifecycle integrity locking\n' "$scenario" >&2; exit 2 ;;
  esac
  printf 'dotfiles_release: running %s\n' "$scenario"
  bash "$test_dir/${scenario}_test.sh"
done

printf 'dotfiles_release: all scenarios passed\n'
