#!/usr/bin/env bash

set -euo pipefail

test_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../scripts/setup-lib
source "$test_dir/../scripts/setup-lib"
# shellcheck source=../scripts/setup-catalog-lib
source "$test_dir/../scripts/setup-catalog-lib"
# shellcheck source=../scripts/setup-tools-lib
source "$test_dir/../scripts/setup-tools-lib"
# shellcheck source=../scripts/setup-system-lib
source "$test_dir/../scripts/setup-system-lib"
# shellcheck source=../scripts/dotfiles-release-lib
source "$test_dir/../scripts/dotfiles-release-lib"
load_tool_catalog "$test_dir/../tools.env"
# shellcheck source=tools/fixture.sh
source "$test_dir/tools/fixture.sh"

health_stage() {
  local label=$1 status
  shift

  printf 'tools_runner: checking %s\n' "$label"
  "$@" && return
  status=$?
  report_error "$label health check failed (status $status)" || true
  return "$status"
}

main() {
  local release=${1:-} health_home tool
  local DOTFILES_IGNORE_USER_BIN=1 VIRTUAL_ENV='' KUBECTL_VERSION='' HELM_VERSION=''
  local PYTHONDONTWRITEBYTECODE=1
  local LC_ALL=C.UTF-8 LANG=C.UTF-8
  local RELEASE_ROOT
  local -a selected_tools=()
  local -A release_metadata=()

  (($# == 1)) || {
    report_error 'usage: tools_runner RELEASE_DIRECTORY'
    return 2
  }
  release=$(readlink -f -- "$release") || return
  RELEASE_ROOT=${release%/*}
  read_release_metadata "$release/release.env" release_metadata || return
  read_release_tools release_metadata selected_tools || return
  health_stage installation env DOTFILES_RELEASE_ROOT="$RELEASE_ROOT" \
    "$release/bin/dotfiles-release" health "${release_metadata[RELEASE_ID]}" || return
  health_home=$(mktemp -d) || return
  TEMP_PATHS+=("$health_home")
  local PATH="$release/bin:/usr/bin:/bin"
  if list_has selected_tools nvim; then
    PATH="$release/bin:$release/share/nvim2/mason/bin:/usr/bin:/bin"
  fi
  local HOME=$health_home XDG_CONFIG_HOME=$health_home/.config
  local XDG_DATA_HOME=$health_home/.local/share XDG_CACHE_HOME=$health_home/.cache
  local XDG_STATE_HOME=$health_home/.local/state
  export PATH HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME
  export DOTFILES_IGNORE_USER_BIN VIRTUAL_ENV KUBECTL_VERSION HELM_VERSION
  export PYTHONDONTWRITEBYTECODE LC_ALL LANG
  mkdir -p "$XDG_CACHE_HOME" "$XDG_STATE_HOME" || return
  for tool in "${selected_tools[@]}"; do
    if [[ $tool == uv ]] && ! list_has selected_tools python; then
      continue
    fi
    if [[ ! -f $test_dir/tools/$tool.sh ]]; then
      continue
    fi
    # shellcheck disable=SC1090
    source "$test_dir/tools/$tool.sh" || return
    health_stage "$tool" "health_${tool//-/_}" "$release" "$health_home" || return
  done
  # shellcheck source=tools/bash.sh
  source "$test_dir/tools/bash.sh" || return
  health_stage Bash health_bash "$release" "$health_home" || return
  verify_installed_manifest "$release" || return
  printf '%s: %s passed offline functional checks\n' "${0##*/}" "${release##*/}"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  TEMP_PATHS=()
  trap cleanup_setup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  main "$@"
fi
