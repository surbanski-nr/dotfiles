#!/usr/bin/env bash

# Test snippets expand variables in their independent shells, not this runner.
# shellcheck disable=SC2016

set -euo pipefail

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
archive_script=$repo_dir/scripts/bash-history-archive
history_library=$repo_dir/bash/.bash_history_lib
test_root=$(mktemp -d)
original_path=$PATH
background_pid=

cleanup() {
  local status=$?
  if [[ -n $background_pid ]]; then
    kill "$background_pid" 2>/dev/null || true
    wait "$background_pid" 2>/dev/null || true
  fi
  find "$test_root" -depth -delete
  exit "$status"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

make_history() {
  local directory=$1 count=$2 unterminated=${3:-0}
  mkdir -p "$directory"
  HISTORY_FIXTURE_DIR=$directory gawk -v count="$count" -v unterminated="$unterminated" '
    BEGIN {
      root = ENVIRON["HISTORY_FIXTURE_DIR"]
      for (i = 1; i <= count; i++) {
        record = sprintf("command-%06d\n", i)
        if (i > 2) record = sprintf("#%d\n", 1700000000 + i) record
        if (i == 80000 || i == 80001)
          record = record "printf '\''first line\n\nzażółć second line'\''\n"
        if (unterminated && i == count) sub(/\n$/, "", record)
        printf "%s", record > (root "/.histfile")
        printf "%s", record > (root "/original")
        printf "%s", record > (root (i <= 80000 ? "/expected-archive" : "/expected-live"))
      }
    }
  '
  chmod 600 "$directory/.histfile"
}

archives() {
  find "$1/.histfile.d" -maxdepth 1 -type f -name 'history-*.hist' -print
}

run_shell() {
  local directory=$1 code=$2 helper=${3:-$archive_script}
  timeout --kill-after=2s 15s env -i HOME="$directory" PATH="$original_path" \
    TERM=dumb TEST_HISTORY_LIBRARY="$history_library" TEST_ARCHIVER="$helper" \
    TEST_REAL_FLOCK="$(command -v flock)" \
    bash --noprofile --norc -i -c '
      set -e
      set +o history
      _dotfiles_warn() { printf "dotfiles: %s\n" "$*" >&2; }
      source "$TEST_HISTORY_LIBRARY" "$TEST_ARCHIVER"
      history -c
      [[ ! -f $HISTFILE ]] || history -r
      eval "$1"
    ' history-test "$code" >"$directory/shell.log" 2>"$directory/shell.err"
}

[[ -f $archive_script ]] || fail 'history archiver is missing'

below=$test_root/below
make_history "$below" 89999
bash "$archive_script" "$below/.histfile"
cmp "$below/original" "$below/.histfile" || fail 'below-threshold history changed'
[[ ! -e $below/.histfile.d ]] || fail 'below-threshold check created an archive'

for count in 90000 94003; do
  directory=$test_root/"history with spaces \\t $count"
  make_history "$directory" "$count" 1
  bash "$archive_script" "$directory/.histfile"
  mapfile -t files < <(archives "$directory")
  [[ ${#files[@]} -eq 1 ]] || fail 'rotation did not publish exactly one archive'
  cmp "$directory/expected-archive" "${files[0]}" || fail 'archive split a history entry'
  cmp "$directory/expected-live" "$directory/.histfile" || fail 'rotation lost retained or overshoot entries'
  [[ $(stat -c %a "${files[0]}") == 600 && $(stat -c %a "$directory/.histfile.d") == 700 ]] ||
    fail 'archive permissions are not private'
  bash "$archive_script" "$directory/.histfile"
  cmp "$directory/expected-archive" "${files[0]}" || fail 'another check overwrote an archive'
  [[ $(archives "$directory" | wc -l) -eq 1 ]] || fail 'small remainder was archived again'
done

linked=$test_root/linked
make_history "$linked" 90000
mv "$linked/.histfile" "$linked/real-history"
ln -s real-history "$linked/.histfile"
bash "$archive_script" "$linked/.histfile"
[[ -L $linked/.histfile ]] || fail 'rotation replaced the user history symlink'
cmp "$linked/expected-live" "$linked/real-history" || fail 'linked history target was not rotated'

fault=$test_root/fault
make_history "$fault" 90000
mkdir -p "$fault/bin"
for command in sync mv; do
  ln -s "$repo_dir/tests/fixtures/bash/history-command" "$fault/bin/$command"
  if PATH="$fault/bin:$original_path" bash "$archive_script" "$fault/.histfile" >"$fault/$command.log" 2>&1; then
    fail "rotation accepted failed $command"
  fi
  cmp "$fault/original" "$fault/.histfile" || fail "failed $command discarded history"
  mapfile -t files < <(archives "$fault")
  if [[ $command == sync ]]; then
    [[ ${#files[@]} -eq 0 ]] || fail 'failed flush published an archive'
  else
    [[ ${#files[@]} -eq 1 ]] || fail 'failed live replacement discarded the published archive'
    cmp "$fault/expected-archive" "${files[0]}" || fail 'failure left a partial published archive'
  fi
  unlink "$fault/bin/$command"
done
[[ -z $(find "$fault/.histfile.d" "$fault" -maxdepth 1 -name '.history-*' -print) ]] ||
  fail 'handled failure left temporary copies behind'

blocked=$test_root/blocked
make_history "$blocked" 90000
mkdir -p "$blocked/elsewhere"
ln -s elsewhere "$blocked/.histfile.d"
if bash "$archive_script" "$blocked/.histfile" >"$blocked/archive.log" 2>&1; then
  fail 'rotation followed an archive directory symlink'
fi
cmp "$blocked/original" "$blocked/.histfile" || fail 'unsafe archive directory changed history'
run_shell "$blocked" '
  history -s "command after failed rotation"
  _dotfiles_history_sync
  _dotfiles_install_history_exit
'
grep -qx 'command after failed rotation' "$blocked/.histfile" || fail 'rotation failure stopped synchronization'
grep -q 'archiv' "$blocked/shell.err" || fail 'rotation failure was not reported'

tick=$test_root/tick
mkdir -p "$tick"
run_shell "$tick" '
  for round in 1 2 3; do
    source "$TEST_HISTORY_LIBRARY" "$TEST_ARCHIVER"
    history -s "command round $round"
    _dotfiles_history_sync
  done
  [[ $(wc -l <"$HOME/archive-checks") -eq 1 ]]
  _DOTFILES_HISTORY_NEXT_CHECK=$SECONDS
  _dotfiles_history_sync
  [[ $(wc -l <"$HOME/archive-checks") -eq 2 ]]
  _dotfiles_install_history_exit
' "$repo_dir/tests/fixtures/bash/history-command"
for round in 1 2 3; do
  [[ $(grep -cx "command round $round" "$tick/.histfile") -eq 1 ]] ||
    fail 'periodic checks or repeated source lost or duplicated a command'
done

shared=$test_root/shared
make_history "$shared" 90000
run_shell "$shared" '
  history -s "command from waiting shell"
  bash --noprofile --norc -i -c '\''
    set +o history
    _dotfiles_warn() { printf "%s\n" "$*" >&2; }
    source "$TEST_HISTORY_LIBRARY" "$TEST_ARCHIVER"
    history -c
    history -r
    history -s "command from rotating shell"
    _dotfiles_history_sync
    _dotfiles_install_history_exit
  '\''
  _dotfiles_history_sync
  _dotfiles_history_sync
  HISTTIMEFORMAT="" history >"$HOME/reloaded-history"
  _dotfiles_install_history_exit
'
for origin in waiting rotating; do
  [[ $(grep -cx "command from $origin shell" "$shared/.histfile") -eq 1 ]] ||
    fail "rotation lost or duplicated the $origin shell command"
  [[ $(grep -c "command from $origin shell" "$shared/reloaded-history") -eq 1 ]] ||
    fail "rotation did not refresh the $origin command in another open shell"
done
[[ $(grep -c '^command-' "$shared/.histfile") -eq 10000 ]] || fail 'stale shell restored archived entries'

packaged=$test_root/packaged
make_history "$packaged" 90000
payload=$packaged/dotfiles-releases/dotfiles-aaaaaaaaaaaa/dotfiles
mkdir -p "$payload/bash" "$payload/scripts"
cp "$repo_dir/bash/.bashrc" "$history_library" "$payload/bash/"
cp "$archive_script" "$payload/scripts/"
ln -s dotfiles-aaaaaaaaaaaa "$packaged/dotfiles-releases/current"
ln -s dotfiles-releases/current/dotfiles/bash/.bashrc "$packaged/.bashrc"
run_shell "$packaged" '
  DOTFILES=$HOME/no-checkout
  source "$HOME/.bashrc"
  history -s "command from standalone payload"
  _dotfiles_history_sync
'
mapfile -t files < <(archives "$packaged")
[[ ${#files[@]} -eq 1 ]] || fail 'packaged .bashrc needed the original repository to archive'
cmp "$packaged/expected-archive" "${files[0]}" || fail 'standalone payload archived different entries'
grep -qx 'command from standalone payload' "$packaged/.histfile" || fail 'standalone payload lost its pending command'

exit_home=$test_root/exit
mkdir -p "$exit_home"
if run_shell "$exit_home" '
  trap '\''printf "foreign-status=%s histfile=%s\n" "$?" "$HISTFILE" >>"$HOME/foreign-exit"; exit 17'\'' EXIT
  _dotfiles_install_history_exit
  source "$TEST_HISTORY_LIBRARY" "$TEST_ARCHIVER"
  _dotfiles_install_history_exit
  history -s "pending command saved at exit"
  set -o history
  exit 17
'; then
  fail 'history exit hook changed the shell exit status'
else
  [[ $? -eq 17 ]] || fail 'foreign EXIT handler did not retain status 17'
fi
[[ $(grep -cx 'pending command saved at exit' "$exit_home/.histfile") -eq 1 ]] ||
  fail 'exit save lost or duplicated the pending command'
[[ $(<"$exit_home/foreign-exit") == "foreign-status=17 histfile=$exit_home/.histfile" ]] ||
  fail 'repeated source duplicated the foreign EXIT hook or changed its environment'

wrapped=$test_root/wrapped
mkdir -p "$wrapped"
run_shell "$wrapped" '
  trap '\''printf "original\n" >>"$HOME/foreign-exit"'\'' EXIT
  _dotfiles_install_history_exit
  old=$(trap -p EXIT)
  old=${old#trap -- }
  old=${old% EXIT}
  eval "old=$old"
  trap "$old; printf '\''appended\n'\'' >>\"\$HOME/foreign-exit\"" EXIT
  source "$TEST_HISTORY_LIBRARY" "$TEST_ARCHIVER"
  _dotfiles_install_history_exit
  history -s "pending with appended hook"
'
[[ $(<"$wrapped/foreign-exit") == $'original\nappended' ]] ||
  fail 'repeated source broke a foreign wrapper around the EXIT hook'

recovery=$test_root/recovery
mkdir -p "$recovery/bin"
ln -s "$repo_dir/tests/fixtures/bash/history-command" "$recovery/bin/flock"
printf 'previous disk command\n' >"$recovery/.histfile"
run_shell "$recovery" '
  history -s "pending during lock failure"
  PATH="$HOME/bin:$PATH"
  _dotfiles_install_history_exit
  set -o history
'
[[ $(<"$recovery/.histfile") == 'previous disk command' ]] || fail 'native exit bypassed the failed lock'
mapfile -t copies < <(find "$recovery" -maxdepth 1 -name '.histfile-unsaved.*' -type f)
[[ ${#copies[@]} -eq 1 && $(stat -c %a "${copies[0]}") == 600 ]] || fail 'exit failure did not preserve a private copy'
grep -qx 'pending during lock failure' "${copies[0]}" || fail 'recovery copy lost the pending command'
grep -Fq "${copies[0]}" "$recovery/shell.err" || fail 'exit failure did not report the recovery path'

write_error=$test_root/write-error
mkdir -p "$write_error"
ln -s /dev/full "$write_error/full-history"
run_shell "$write_error" '
  history -s "command before disk-full write"
  HISTFILE=$HOME/full-history
  _DOTFILES_HISTORY_NEXT_CHECK=$((SECONDS + 300))
  if _dotfiles_history_sync; then exit 1; fi
  HISTFILE=$HOME/.histfile
  history -s "command after disk recovery"
  _dotfiles_history_sync
  _dotfiles_install_history_exit
'
mapfile -t copies < <(find "$write_error" -maxdepth 1 -name '.histfile-unsaved.*' -type f)
[[ ${#copies[@]} -eq 1 ]] || fail 'failed write did not immediately preserve memory history'
grep -qx 'command before disk-full write' "${copies[0]}" || fail 'disk-full failure lost the earlier command'
grep -qx 'command after disk recovery' "$write_error/.histfile" || fail 'write recovery stopped future synchronization'
grep -Fq "${copies[0]}" "$write_error/shell.err" || fail 'failed write did not report its recovery path'

no_backup=$test_root/no-backup
mkdir -p "$no_backup/bin"
ln -s /dev/full "$no_backup/full-history"
ln -s "$repo_dir/tests/fixtures/bash/history-command" "$no_backup/bin/mktemp"
run_shell "$no_backup" '
  real_path=$PATH
  PATH="$HOME/bin:$PATH"
  history -s "command awaiting available recovery storage"
  HISTFILE=$HOME/full-history
  _DOTFILES_HISTORY_NEXT_CHECK=$((SECONDS + 300))
  if _dotfiles_history_sync; then exit 1; fi
  source "$TEST_HISTORY_LIBRARY" "$TEST_ARCHIVER"
  history -s "command written after disk recovery"
  if _dotfiles_history_sync; then exit 1; fi
  HISTTIMEFORMAT="" history >"$HOME/memory-before-backup"
  PATH=$real_path
  _dotfiles_history_sync
  _dotfiles_install_history_exit
'
grep -q 'command awaiting available recovery storage' "$no_backup/memory-before-backup" ||
  fail 'failed recovery storage discarded the only memory copy'
mapfile -t copies < <(find "$no_backup" -maxdepth 1 -name '.histfile-unsaved.*' -type f)
[[ ${#copies[@]} -eq 1 ]] || fail 'recovered storage did not preserve the earlier memory history'
for entry in 'command awaiting available recovery storage' 'command written after disk recovery'; do
  grep -qx "$entry" "${copies[0]}" || fail 'recovered backup omitted an unsaved command'
done

serialized=$test_root/serialized
make_history "$serialized" 90000
exec {lock_fd}>>"$serialized/.histfile.lock"
flock "$lock_fd"
bash "$archive_script" "$serialized/.histfile" &
background_pid=$!
# The child cannot publish while our descriptor holds the same lock.
sleep 0.1
kill -0 "$background_pid" || fail 'archiver did not wait for the writer lock'
cmp "$serialized/original" "$serialized/.histfile" || fail 'rotation bypassed the writer lock'
flock -u "$lock_fd"
exec {lock_fd}>&-
wait "$background_pid"
background_pid=
cmp "$serialized/expected-live" "$serialized/.histfile" || fail 'waiting rotation failed after lock release'

exit_locked=$test_root/exit-locked
mkdir -p "$exit_locked/bin"
ln -s "$repo_dir/tests/fixtures/bash/history-command" "$exit_locked/bin/flock"
printf 'previous disk command\n' >"$exit_locked/.histfile"
mkfifo "$exit_locked/writer-ready"
exec {ready_fd}<>"$exit_locked/writer-ready"
exec {lock_fd}>>"$exit_locked/.histfile.lock"
flock "$lock_fd"
run_shell "$exit_locked" '
  export TEST_FLOCK_READY=$HOME/writer-ready
  PATH="$HOME/bin:$PATH"
  history -s "command saved after waiting on exit"
  _dotfiles_install_history_exit
  set -o history
' &
background_pid=$!
read -r -t 5 -u "$ready_fd" message || fail 'exit writer did not reach the shared lock'
[[ $message == waiting && $(<"$exit_locked/.histfile") == 'previous disk command' ]] ||
  fail 'exit writer bypassed the held rotation lock'
flock -u "$lock_fd"
exec {lock_fd}>&-
wait "$background_pid"
background_pid=
exec {ready_fd}>&-
[[ $(grep -cx 'command saved after waiting on exit' "$exit_locked/.histfile") -eq 1 ]] ||
  fail 'waiting exit save lost or duplicated the pending command'
[[ -z $(find "$exit_locked" -maxdepth 1 -name '.histfile-unsaved.*' -print) ]] ||
  fail 'successful waiting exit save unnecessarily created a recovery copy'

printf 'Bash history archival tests passed\n'
