#!/usr/bin/env bash

health_uv() {
  local bin=$1 health_home=$2
  local work=$health_home/uv
  local python=${3:-$bin/python3}

  mkdir -p "$work" || return
  PYTHONDONTWRITEBYTECODE=1 "$bin/uv" venv --no-config --offline \
    --no-cache --no-python-downloads --python "$python" "$work/uv-venv" || return
  "$work/uv-venv/bin/python" -I -B - <<'PY' || return
import hashlib
import json
import sqlite3
import ssl
import sys
import venv

assert sys.prefix != sys.base_prefix
print('uv-venv-ok')
PY
}
