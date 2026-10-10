#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
fixture_bin=$repo_dir/tests/fixtures/scripts

cleanup() {
  find "$test_root" -depth -delete
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_status() {
  [[ $status -eq $1 ]] ||
    fail "$2: expected status $1, got $status; output: $output"
}

assert_contains() {
  [[ $1 == *"$2"* ]] || fail "$3: missing '$2' in: $1"
}

run_command() {
  set +e
  output=$("$@" 2>&1)
  status=$?
  set -e
}

run_command "$repo_dir/scripts/color-contrast" '#008080' '#ffffff'
assert_status 0 'color-contrast teal against white'
assert_contains "$output" '#008080    4.77:1' 'color-contrast WCAG ratio'
assert_contains "$output" 'pass fail pass' 'color-contrast WCAG levels'
assert_contains "$output" '7.0+        AAA normal text; very strong' \
  'color-contrast WCAG guide'

run_command "$repo_dir/scripts/color-contrast" --shades 2 '#008080' '#ffffff'
assert_status 0 'color-contrast shade generation'
assert_contains "$output" '#002B2B' 'color-contrast darker shade'
assert_contains "$output" '#55AAAA' 'color-contrast lighter shade'

run_command "$repo_dir/scripts/color-contrast" '#GG0000' '#ffffff'
[[ $status -ne 0 ]] || fail 'color-contrast accepted an invalid color'
assert_contains "$output" 'expected #RRGGBB' 'color-contrast invalid color error'

run_in() {
  local directory=$1
  shift

  set +e
  output=$(cd "$directory" && "$@" 2>&1)
  status=$?
  set -e
}

init_remote() {
  local root=$1
  local branch=$2

  seed=$root/seed
  origin=$root/origin.git
  work=$root/work
  mkdir -p "$root"
  git init -q -b "$branch" "$seed"
  git -C "$seed" config user.name fixture
  git -C "$seed" config user.email fixture@example.invalid
  printf 'initial\n' >"$seed/conflict"
  git -C "$seed" add conflict
  git -C "$seed" commit -qm initial
  git clone -q --bare "$seed" "$origin"
  git -C "$origin" symbolic-ref HEAD "refs/heads/$branch"
  git clone -q "$origin" "$work"
  git -C "$work" config user.name fixture
  git -C "$work" config user.email fixture@example.invalid
}

git_root=$test_root/git-main
init_remote "$git_root" main
git -C "$work" switch -qc feature
printf 'uncommitted\n' >"$work/local-change"
run_in "$work" "$repo_dir/scripts/m"
assert_status 0 'm origin/HEAD branch'
[[ $(git -C "$work" branch --show-current) == main ]] ||
  fail 'm did not select origin/HEAD main branch'
[[ $(<"$work/local-change") == uncommitted ]] ||
  fail 'm did not preserve an uncommitted file'

git_root=$test_root/git-master
init_remote "$git_root" master
git -C "$work" update-ref -d refs/remotes/origin/HEAD
git -C "$work" switch -qc topic
run_in "$work" "$repo_dir/scripts/m"
assert_status 0 'm master fallback'
[[ $(git -C "$work" branch --show-current) == master ]] ||
  fail 'm did not use the master fallback'

git_root=$test_root/git-obstructed
init_remote "$git_root" main
git -C "$work" switch -qc topic
printf 'topic\n' >"$work/conflict"
git -C "$work" commit -qam topic
printf 'dirty\n' >"$work/conflict"
run_in "$work" "$repo_dir/scripts/m"
[[ $status -ne 0 ]] || fail 'm ignored an obstructed branch switch'
[[ $(git -C "$work" branch --show-current) == topic ]] ||
  fail 'm continued after an obstructed branch switch'
[[ $(<"$work/conflict") == dirty ]] || fail 'm changed an obstructed work tree'

git_root=$test_root/git-diverged
init_remote "$git_root" main
printf 'local\n' >>"$work/conflict"
git -C "$work" commit -qam local
updater=$git_root/updater
git clone -q "$origin" "$updater"
git -C "$updater" config user.name fixture
git -C "$updater" config user.email fixture@example.invalid
printf 'remote\n' >>"$updater/conflict"
git -C "$updater" commit -qam remote
git -C "$updater" push -q origin main
run_in "$work" "$repo_dir/scripts/m"
[[ $status -ne 0 ]] || fail 'm accepted a divergent pull'

git_root=$test_root/git-pull-failure
init_remote "$git_root" main
git -C "$work" remote set-url origin "$git_root/missing.git"
run_in "$work" "$repo_dir/scripts/m"
[[ $status -ne 0 ]] || fail 'm hid a pull failure'

home_dir=$test_root/'home with spaces'
xdg_dir=$test_root/xdg
mkdir -p "$home_dir" "$xdg_dir"
command_log=$test_root/kubectl.log
context_file=$home_dir/kube-backup-contexts.txt
printf ' # comment\r\n prod context \r\nprod context\nempty\nliteral ; touch injected' >"$context_file"
context_before=$(sha256sum "$context_file")
run_in "$test_root" env HOME="$home_dir" XDG_CONFIG_HOME="$xdg_dir" \
  PATH="$fixture_bin:$PATH" TEST_COMMAND_LOG="$command_log" \
  "$repo_dir/scripts/checkbackups"
assert_status 0 'checkbackups valid contexts'
assert_contains "$output" $'two\tfailed backup\tFailed' 'checkbackups structured status'
assert_contains "$output" 'No unfinished or failed backups.' 'checkbackups empty result'
[[ $(sha256sum "$context_file") == "$context_before" ]] ||
  fail 'checkbackups changed its context file'
[[ ! -e $test_root/injected ]] || fail 'checkbackups evaluated a context entry'
[[ $(grep -Fxc $'ARG\tprod context' "$command_log") -eq 1 ]] ||
  fail 'checkbackups did not deduplicate a literal context'
[[ $(grep -Fxc $'ARG\tliteral ; touch injected' "$command_log") -eq 1 ]] ||
  fail 'checkbackups changed a literal context value'
[[ ! -e $xdg_dir/kube-backup-contexts.txt ]] ||
  fail 'checkbackups created an XDG context file'

printf 'prod context\nbad\n' >"$context_file"
run_command env HOME="$home_dir" PATH="$fixture_bin:$PATH" \
  "$repo_dir/scripts/checkbackups"
[[ $status -ne 0 ]] || fail 'checkbackups hid a mixed API failure'
assert_contains "$output" 'failed backup' 'checkbackups lost successful context output'
assert_contains "$output" 'failed to query context: bad' 'checkbackups context error'

printf '# only a comment\n  \r\n' >"$context_file"
run_command env HOME="$home_dir" PATH="$fixture_bin:$PATH" \
  "$repo_dir/scripts/checkbackups"
[[ $status -ne 0 ]] || fail 'checkbackups accepted an effectively empty list'
assert_contains "$output" "$context_file" 'checkbackups empty-list path'
rm "$context_file"
run_command env HOME="$home_dir" PATH="$fixture_bin:$PATH" \
  "$repo_dir/scripts/checkbackups"
[[ $status -ne 0 ]] || fail 'checkbackups accepted a missing list'

prefix_file=$home_dir/kube-log-prefixes.txt
printf '# prefixes\r\n api \r\napi-good\napi' >"$prefix_file"
prefix_before=$(sha256sum "$prefix_file")
dump_dir=$test_root/dump
mkdir "$dump_dir"
: >"$command_log"
run_in "$dump_dir" env HOME="$home_dir" XDG_CONFIG_HOME="$xdg_dir" \
  PATH="$fixture_bin:$PATH" TEST_COMMAND_LOG="$command_log" \
  "$repo_dir/scripts/dumplogs" 15m
[[ $status -ne 0 ]] || fail 'dumplogs hid a partial log failure'
assert_contains "$output" 'Logs for api-good-1 saved' 'dumplogs successful save'
assert_contains "$output" 'failed to download logs for pod: api-bad-2' \
  'dumplogs per-pod failure'
log_dir=$(find "$dump_dir" -maxdepth 1 -type d -name '*_kubernetes-logs' -print)
[[ -n $log_dir ]] || fail 'dumplogs did not create its neutral output directory'
[[ $(find "$log_dir" -type f -name '*api-good-1.log' | wc -l) -eq 1 ]] ||
  fail 'dumplogs did not retain the successful log'
[[ $(find "$log_dir" -type f -name '*api-bad-2.log' | wc -l) -eq 0 ]] ||
  fail 'dumplogs promoted a failed log'
[[ $(find "$log_dir" -type f -name '.*' | wc -l) -eq 0 ]] ||
  fail 'dumplogs left a temporary log'
[[ $(grep -Fxc $'ARG\t--since=15m' "$command_log") -eq 2 ]] ||
  fail 'dumplogs did not forward --since to each matched pod'
[[ $(grep -Fxc $'ARG\tget' "$command_log") -eq 1 ]] ||
  fail 'dumplogs fetched the pod inventory more than once'
[[ $(sha256sum "$prefix_file") == "$prefix_before" ]] ||
  fail 'dumplogs changed its prefix file'
[[ ! -e $xdg_dir/kube-log-prefixes.txt ]] ||
  fail 'dumplogs created an XDG prefix file'

no_match_dir=$test_root/no-match
mkdir "$no_match_dir"
printf 'api\n' >"$prefix_file"
run_in "$no_match_dir" env HOME="$home_dir" PATH="$fixture_bin:$PATH" \
  TEST_KUBECTL_SCENARIO=no-pod-match "$repo_dir/scripts/dumplogs"
assert_status 0 'dumplogs no matches'
assert_contains "$output" 'No pods matched' 'dumplogs no-match message'
[[ -z $(find "$no_match_dir" -mindepth 1 -print -quit) ]] ||
  fail 'dumplogs created output for zero matches'

run_command env HOME="$home_dir" PATH="$fixture_bin:$PATH" \
  TEST_KUBECTL_SCENARIO=pod-list-fail "$repo_dir/scripts/dumplogs"
[[ $status -ne 0 ]] || fail 'dumplogs hid a pod-list failure'
rm "$prefix_file"
run_command env HOME="$home_dir" PATH="$fixture_bin:$PATH" \
  "$repo_dir/scripts/dumplogs"
[[ $status -ne 0 ]] || fail 'dumplogs accepted a missing prefix list'

run_command env PATH="$fixture_bin:$PATH" TEST_KUBECTL_SCENARIO=nodes-empty \
  "$repo_dir/scripts/findpodsonnodepool" 'pool=empty value'
assert_status 0 'findpodsonnodepool empty result'
assert_contains "$output" 'No nodes found' 'findpodsonnodepool empty message'
run_command env PATH="$fixture_bin:$PATH" TEST_KUBECTL_SCENARIO=nodes-fail \
  "$repo_dir/scripts/findpodsonnodepool" pool=broken
[[ $status -ne 0 ]] || fail 'findpodsonnodepool hid node-list failure'
run_command env PATH="$fixture_bin:$PATH" TEST_KUBECTL_SCENARIO=node-pods-fail \
  "$repo_dir/scripts/findpodsonnodepool" pool=workers
[[ $status -ne 0 ]] || fail 'findpodsonnodepool hid a per-node failure'
assert_contains "$output" 'fixture pod output' 'findpodsonnodepool successful node'
assert_contains "$output" 'failed to list pods on node: node-b' \
  'findpodsonnodepool failed node'

run_command env PATH="$fixture_bin:$PATH" "$repo_dir/scripts/curr"
assert_status 0 'curr named namespace'
assert_contains "$output" 'Current context:   fixture-context' 'curr context'
assert_contains "$output" 'Current namespace: fixture-namespace' 'curr namespace'
run_command env PATH="$fixture_bin:$PATH" TEST_KUBECTL_SCENARIO=curr-default \
  "$repo_dir/scripts/curr"
assert_status 0 'curr default namespace'
assert_contains "$output" 'Current namespace: default' 'curr default output'
run_command env PATH="$fixture_bin:$PATH" TEST_KUBECTL_SCENARIO=curr-context-fail \
  "$repo_dir/scripts/curr"
[[ $status -ne 0 ]] || fail 'curr hid current-context failure'
run_command env PATH="$fixture_bin:$PATH" TEST_KUBECTL_SCENARIO=curr-namespace-fail \
  "$repo_dir/scripts/curr"
[[ $status -ne 0 ]] || fail 'curr hid namespace failure'

psql_log=$test_root/psql.log
database_json='["alpha","quote\"db"]'
run_command env PATH="$fixture_bin:$PATH" TEST_COMMAND_LOG="$psql_log" \
  TEST_PSQL_OUTPUT="$database_json" "$repo_dir/scripts/postgres-db-list"
assert_status 0 'postgres-db-list JSON output'
[[ $output == "$database_json" ]] || fail 'postgres-db-list changed JSON output'
grep -Fx $'ARG\t-X' "$psql_log" >/dev/null || fail 'postgres-db-list omitted -X'
grep -Fx $'ARG\tON_ERROR_STOP=1' "$psql_log" >/dev/null ||
  fail 'postgres-db-list omitted ON_ERROR_STOP'
grep -F 'json_agg(datname ORDER BY datname)' "$psql_log" >/dev/null ||
  fail 'postgres-db-list does not generate JSON in SQL'
run_command env PATH="$fixture_bin:$PATH" TEST_PSQL_OUTPUT='[]' \
  "$repo_dir/scripts/postgres-db-list"
assert_status 0 'postgres-db-list empty list'
[[ $output == '[]' ]] || fail 'postgres-db-list changed an empty list'
run_command env PATH="$fixture_bin:$PATH" TEST_PSQL_OUTPUT= \
  "$repo_dir/scripts/postgres-db-list"
[[ $status -ne 0 ]] || fail 'postgres-db-list accepted missing query output'
run_command env PATH="$fixture_bin:$PATH" TEST_PSQL_FAIL=1 \
  "$repo_dir/scripts/postgres-db-list"
[[ $status -ne 0 ]] || fail 'postgres-db-list hid a query failure'

notes_root=$test_root/'notes with spaces'
mkdir -p "$notes_root"
nvim_log=$test_root/nvim.log
run_command env PATH="$fixture_bin:$PATH" NOTES="$notes_root" \
  SECOND_BRAIN="$test_root/wrong-notes" TEST_COMMAND_LOG="$nvim_log" \
  "$repo_dir/scripts/day"
assert_status 0 'day creates a note'
note=$notes_root/periodic-notes/daily-notes/2026-09-26.md
[[ -f $note ]] || fail 'day did not create the daily note under NOTES'
expected_note=$test_root/expected-note
cat >"$expected_note" <<'EOF'
# 2026-09-26

[[2026-09-25]] - [[2026-09-27]]

## Intention

What do I want to achieve today and tomorrow?

## Tracking

- [ ] Something to track

## Log
EOF
cmp "$expected_note" "$note" || fail 'day created unexpected note content'
grep -Fx 'NVIM_APPNAME=nvim2' "$nvim_log" >/dev/null ||
  fail 'day did not select Nvim2'
grep -Fx $'ARG\t+normal Gzzo' "$nvim_log" >/dev/null ||
  fail 'day did not open at the end of the note'

printf 'existing bytes without newline' >"$note"
cp "$note" "$test_root/note-before"
run_command env PATH="$fixture_bin:$PATH" NOTES="$notes_root" \
  TEST_COMMAND_LOG="$nvim_log" "$repo_dir/scripts/day"
assert_status 0 'day opens an existing note'
cmp "$test_root/note-before" "$note" || fail 'day overwrote an existing note'

compat_root=$test_root/compat-notes
mkdir "$compat_root"
run_command env -u NOTES PATH="$fixture_bin:$PATH" SECOND_BRAIN="$compat_root" \
  "$repo_dir/scripts/day"
assert_status 0 'day SECOND_BRAIN compatibility'
[[ -f $compat_root/periodic-notes/daily-notes/2026-09-26.md ]] ||
  fail 'day ignored SECOND_BRAIN compatibility'

run_command env -u NOTES -u SECOND_BRAIN PATH="$fixture_bin:$PATH" \
  "$repo_dir/scripts/day"
[[ $status -ne 0 ]] || fail 'day accepted missing notes configuration'

failure_root=$test_root/failing-editor
mkdir "$failure_root"
run_command env PATH="$fixture_bin:$PATH" NOTES="$failure_root" TEST_NVIM_FAIL=1 \
  "$repo_dir/scripts/day"
assert_status 53 'day editor failure'
[[ -f $failure_root/periodic-notes/daily-notes/2026-09-26.md ]] ||
  fail 'day removed a safely created note after editor failure'

unsafe_root=$test_root/unsafe-note
mkdir -p "$unsafe_root/periodic-notes/daily-notes"
printf 'target\n' >"$unsafe_root/target"
ln -s "$unsafe_root/target" \
  "$unsafe_root/periodic-notes/daily-notes/2026-09-26.md"
run_command env PATH="$fixture_bin:$PATH" NOTES="$unsafe_root" \
  "$repo_dir/scripts/day"
[[ $status -ne 0 ]] || fail 'day accepted a symlink note target'
[[ $(<"$unsafe_root/target") == target ]] || fail 'day changed a symlink target'

run_command env PATH="$fixture_bin:$PATH" TEST_WEEK=08 "$repo_dir/scripts/week"
assert_status 0 'week 08'
[[ $output == 'Current week is: 08' ]] || fail 'week did not preserve leading zero 08'
run_command env PATH="$fixture_bin:$PATH" TEST_WEEK=09 "$repo_dir/scripts/week"
assert_status 0 'week 09'
[[ $output == 'Current week is: 09' ]] || fail 'week did not preserve leading zero 09'

reconcile_home=$test_root/reconcile-home
mkdir "$reconcile_home"
printf 'context bytes' >"$reconcile_home/kube-backup-contexts.txt"
printf 'prefix bytes' >"$reconcile_home/kube-log-prefixes.txt"
cp "$reconcile_home/kube-backup-contexts.txt" "$test_root/context-before"
cp "$reconcile_home/kube-log-prefixes.txt" "$test_root/prefix-before"
run_in "$repo_dir" ./bstow -t "$reconcile_home" stow bash
assert_status 0 'bstow reconciliation with local kube inputs'
cmp "$test_root/context-before" "$reconcile_home/kube-backup-contexts.txt" ||
  fail 'bstow changed kube-backup-contexts.txt'
cmp "$test_root/prefix-before" "$reconcile_home/kube-log-prefixes.txt" ||
  fail 'bstow changed kube-log-prefixes.txt'

printf 'Script tests passed\n'
