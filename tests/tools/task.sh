#!/usr/bin/env bash

health_task() {
  local bin=$1 health_home=$2
  local work=$health_home/task

  mkdir -p "$work" || return
  printf '%s\n' \
    "version: '3'" \
    'tasks:' \
    '  health:' \
    '    cmds:' \
    '      - test -f marker' \
    '    silent: true' >"$work/Taskfile.yml" || return
  : >"$work/marker" || return
  "$bin/task" --dir "$work" --taskfile "$work/Taskfile.yml" health || return
}
