#!/usr/bin/env bash

health_rg() {
  local bin=$1 health_home=$2 output
  local work=$health_home/rg

  mkdir -p "$work" || return
  printf 'alpha\noffline needle\nomega\n' >"$work/input.txt" || return
  output=$("$bin/rg" --fixed-strings 'offline needle' "$work/input.txt") || return
  printf '%s\n' "$output"
  [[ $output == *'offline needle'* ]] || {
    report_error 'ripgrep functional check failed'
    return 1
  }
}
