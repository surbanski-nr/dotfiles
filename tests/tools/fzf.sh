#!/usr/bin/env bash

health_fzf() {
  local release=$1 health_home=$2 output
  local work=$health_home/fzf

  mkdir -p "$work" || return
  output=$(printf 'alpha\noffline needle\nomega\n' | "$release/bin/fzf" --filter='offline needle') || return
  printf '%s\n' "$output"
  [[ $output == 'offline needle' ]] || {
    report_error 'fzf functional check failed'
    return 1
  }
}
