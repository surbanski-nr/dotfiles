#!/usr/bin/env bash

set -euo pipefail

if [[ ${1:-} == version ]]; then
  exec "${NVIM2_REAL_GOLANGCI_LINT:?}" "$@"
fi

gate=${NVIM2_LINT_GATE:?}
result=$gate/result-$BASHPID.json
"${NVIM2_REAL_GOLANGCI_LINT:?}" "$@" >"$result"
touch "$gate/ready"
for ((attempt = 0; attempt < 400; attempt++)); do
  if [[ -f $gate/release ]]; then
    exec /usr/bin/cat "$result"
  fi
  sleep 0.05
done
printf 'Go lint fixture was not released\n' >&2
exit 124
