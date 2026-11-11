#!/usr/bin/env bash

health_zoxide() {
  local bin=$1 health_home=$2 output
  local work=$health_home/zoxide

  mkdir -p "$work" || return
  mkdir -p "$work/project" || return
  _ZO_DATA_DIR="$work/zoxide" "$bin/zoxide" add "$work/project" || return
  output=$(_ZO_DATA_DIR="$work/zoxide" "$bin/zoxide" query project) || return
  printf 'zoxide-query=%s\n' "$output"
  [[ $output == "$work/project" ]] || {
    report_error 'zoxide database check failed'
    return 1
  }
  "$bin/zoxide" init bash | grep --fixed-strings '__zoxide_hook' || return
}
