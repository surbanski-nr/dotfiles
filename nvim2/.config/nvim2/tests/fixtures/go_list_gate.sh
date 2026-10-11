#!/usr/bin/env bash

set -euo pipefail

parent=
IFS= read -r -d '' parent <"/proc/$PPID/cmdline" || true
if [[ ${1:-} == list && $parent == *golangci-lint ]]; then
  gate=${NVIM2_LINT_GATE:?}
  touch "$gate/loading-$PPID"
  for ((attempt = 0; attempt < 400; attempt++)); do
    if [[ -f $gate/release ]]; then
      exec "${NVIM2_REAL_GO:?}" "$@"
    fi
    sleep 0.05
  done
  printf 'Go package loading fixture was not released\n' >&2
  exit 124
fi
exec "${NVIM2_REAL_GO:?}" "$@"
