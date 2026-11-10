#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

TEMP_PATHS=(caller-owned)
TOOLS=(caller-owned)
RELEASE_ROOT=caller-owned
TRANSACTION_ACTIVE=caller-owned
CANDIDATE_DIR=caller-owned

for library in "$repo_dir/scripts/"*-lib; do
  (
    # Libraries define functions. Their caller owns imports, options and state.
    source() {
      fail "$library implicitly sourced $1"
    }
    trap ':' EXIT INT TERM
    before_options=$SHELLOPTS:$BASHOPTS
    before_traps=$(trap -p)
    before_directory=$PWD
    before_state=$(declare -p TEMP_PATHS TOOLS RELEASE_ROOT TRANSACTION_ACTIVE CANDIDATE_DIR)

    builtin source "$library"

    [[ $SHELLOPTS:$BASHOPTS == "$before_options" ]] || fail "$library changed shell options"
    [[ $(trap -p) == "$before_traps" ]] || fail "$library changed caller traps"
    [[ $PWD == "$before_directory" ]] || fail "$library changed the working directory"
    [[ $(declare -p TEMP_PATHS TOOLS RELEASE_ROOT TRANSACTION_ACTIVE CANDIDATE_DIR) == "$before_state" ]] ||
      fail "$library initialized caller state"
  )
done

(
  # Catalog validation must work without recipe or installer functions.
  source "$repo_dir/scripts/setup-lib"
  source "$repo_dir/scripts/setup-catalog-lib"
  load_config "$repo_dir/tools.env"
  validate_tool_config
)

(
  trap ':' EXIT INT TERM
  before_traps=$(trap -p)
  source "$repo_dir/tests/tools_runner.sh"
  [[ $(trap -p) == "$before_traps" && ${TEMP_PATHS[*]} == caller-owned &&
    $TRANSACTION_ACTIVE == caller-owned ]] ||
    fail 'functional runner initialized the release CLI lifecycle'
)

printf 'setup_architecture: passed\n'
