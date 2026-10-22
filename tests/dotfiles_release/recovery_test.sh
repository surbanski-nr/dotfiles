#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

failure_bin=$test_root/failure-bin
mkdir -p "$failure_bin"
for signal in TERM INT; do
  test_home=$test_root/signal-$signal-home
  mkdir -p "$test_home"
  printf 'signal baseline\n' >"$test_home/.bashrc"
  cat >"$failure_bin/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source_path=${@: -2:1}
destination=${!#}
/usr/bin/mv "$@"
if [[ $source_path == "$HOME/.bashrc" && $destination == "$HOME/.bashrc.before-dotfiles-release" ]]; then
  kill -s "$FIXTURE_SIGNAL" "$PPID"
fi
EOF
  chmod 0755 "$failure_bin/mv"
  status=0
  FIXTURE_SIGNAL=$signal PATH="$failure_bin:/usr/bin:/bin" \
    run_manager install "$artifact_one" >"$test_root/signal-$signal.log" 2>&1 || status=$?
  expected=143
  [[ $signal != INT ]] || expected=130
  [[ $status == "$expected" && $(<"$test_home/.bashrc") == 'signal baseline' &&
    ! -e $test_home/.bashrc.before-dotfiles-release &&
    ! -e $test_home/dotfiles-releases/$id_one &&
    ! -L $test_home/dotfiles-releases/current ]] ||
    fail "$signal did not restore the changed paths and clean the candidate"
  unlink "$failure_bin/mv"
  run_manager install "$artifact_one" >/dev/null
  run_manager uninstall >/dev/null
done

test_home=$test_root/interrupted-import-home
mkdir -p "$test_home/dotfiles-releases/$id_one"
printf 'unfinished user data\n' >"$test_home/dotfiles-releases/$id_one/unfinished"
run_manager list >"$test_root/interrupted-list.log"
[[ $(wc -l <"$test_root/interrupted-list.log") == 1 ]] ||
  fail 'list exposed an unprepared directory as an installed release'
if run_manager set "$id_one" >/dev/null 2>&1; then fail 'set activated an unprepared directory'; fi
if run_manager install "$artifact_one" >/dev/null 2>&1; then
  fail 'install overwrote an unfinished directory'
fi
[[ $(<"$test_home/dotfiles-releases/$id_one/unfinished") == 'unfinished user data' ]] ||
  fail 'retry silently removed an unfinished directory'
run_manager uninstall "$id_one" >/dev/null
run_manager install "$artifact_one" >/dev/null
assert_link "$test_home/dotfiles-releases/current" "$id_one"

printf 'dotfiles_release: recovery passed\n'
