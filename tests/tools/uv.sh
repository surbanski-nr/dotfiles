#!/usr/bin/env bash

health_uv() {
  local release=$1 health_home=$2
  local work=$health_home/uv

  mkdir -p "$work" || return
  PYTHONDONTWRITEBYTECODE=1 "$release/bin/uv" venv --no-config --offline \
    --no-cache --no-python-downloads --python "$release/tools/python/bin/python3" "$work/uv-venv" || return
  "$work/uv-venv/bin/python" -I -B -c \
    'import json, ssl, sys; assert sys.prefix != sys.base_prefix; print("uv-venv-ok")' || return
}
