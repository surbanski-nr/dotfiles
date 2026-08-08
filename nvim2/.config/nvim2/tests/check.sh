#!/usr/bin/env bash

set -euo pipefail

config_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
xdg_config_home=$(dirname -- "$config_dir")
app_name=$(basename -- "$config_dir")
timeout_seconds=${NVIM2_CHECK_TIMEOUT_SECONDS:-60}
runs=${NVIM2_BENCHMARK_RUNS:-5}

if ! [[ $runs =~ ^[1-9][0-9]*$ ]]; then
  printf 'NVIM2_BENCHMARK_RUNS must be a positive integer\n' >&2
  exit 2
fi
if [[ -n ${NVIM2_MAX_STARTUP_MS:-} ]] && ! [[ $NVIM2_MAX_STARTUP_MS =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  printf 'NVIM2_MAX_STARTUP_MS must be a positive number\n' >&2
  exit 2
fi

timeout "$timeout_seconds" env \
  XDG_CONFIG_HOME="$xdg_config_home" \
  NVIM_APPNAME="$app_name" \
  NVIM2_CHECK_TOOLS="${NVIM2_CHECK_TOOLS:-1}" \
  nvim --headless "+lua dofile(vim.fn.stdpath('config') .. '/tests/smoke.lua')"

temporary_dir=$(mktemp -d)
trap 'rm -r -- "$temporary_dir"' EXIT
times_file="$temporary_dir/times"

for ((run = 1; run <= runs; run++)); do
  startup_log="$temporary_dir/startup-$run.log"
  timeout "$timeout_seconds" env \
    XDG_CONFIG_HOME="$xdg_config_home" \
    NVIM_APPNAME="$app_name" \
    nvim --headless --startuptime "$startup_log" '+qa!'
  awk '/NVIM STARTED/ { value = $1 } END { if (value == "") exit 1; print value }' "$startup_log" >> "$times_file"
done

minimum=$(sort -n "$times_file" | awk 'NR == 1 { print; exit }')
median_position=$(( (runs + 1) / 2 ))
median=$(sort -n "$times_file" | awk -v position="$median_position" 'NR == position { print; exit }')
maximum=$(sort -nr "$times_file" | awk 'NR == 1 { print; exit }')
printf 'Nvim2 startup: median %s ms, min %s ms, max %s ms (%d runs)\n' "$median" "$minimum" "$maximum" "$runs"

if [[ -n ${NVIM2_STARTUP_LOG:-} ]]; then
  cp -- "$startup_log" "$NVIM2_STARTUP_LOG"
  printf 'Last startup profile: %s\n' "$NVIM2_STARTUP_LOG"
fi

if [[ -n ${NVIM2_MAX_STARTUP_MS:-} ]] && ! awk -v measured="$median" -v limit="$NVIM2_MAX_STARTUP_MS" 'BEGIN { exit !(measured <= limit) }'; then
  printf 'Nvim2 startup median %s ms exceeds limit %s ms\n' "$median" "$NVIM2_MAX_STARTUP_MS" >&2
  exit 1
fi
