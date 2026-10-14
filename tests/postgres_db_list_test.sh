#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for command_name in initdb pg_ctl psql; do
  command -v "$command_name" >/dev/null || {
    printf 'Required command is missing: %s. Run task test:postgres.\n' "$command_name" >&2
    exit 1
  }
done

test_root=$(mktemp -d)
cleanup() {
  local status=$?
  trap - EXIT
  set +e
  if [[ -f $test_root/data/postmaster.pid ]]; then
    pg_ctl -D "$test_root/data" -m immediate -w -t 10 stop >>"$test_root/server.log" 2>&1
  fi
  if ((status != 0)); then cat "$test_root"/*.log >&2; fi
  find "$test_root" -depth -delete
  exit "$status"
}
trap cleanup EXIT

export HOME=$test_root PGHOST=$test_root/socket PGPORT=5432 PGDATABASE=postgres PGUSER
PGUSER=$(id -un)
mkdir -p "$PGHOST"
printf '\\echo private psql startup\n' >"$HOME/.psqlrc"
initdb -D "$test_root/data" --auth=trust --no-locale --encoding=UTF8 \
  >"$test_root/init.log" 2>&1
pg_ctl -D "$test_root/data" -l "$test_root/server.log" -w -t 15 \
  -o "-F -c listen_addresses='' -k '$PGHOST'" start >"$test_root/start.log" 2>&1
psql -X -v ON_ERROR_STOP=1 -c 'CREATE DATABASE alpha;' \
  -c 'CREATE DATABASE "quote""db";' >"$test_root/create.log" 2>&1

output=$(bash "$repo_dir/scripts/postgres-db-list")
expected='["alpha", "postgres", "quote\"db", "template0", "template1"]'
[[ $output == "$expected" ]] || {
  printf 'FAIL: expected sorted, escaped database names, got: %s\n' "$output" >&2
  exit 1
}

printf 'Postgres database list test passed\n'
