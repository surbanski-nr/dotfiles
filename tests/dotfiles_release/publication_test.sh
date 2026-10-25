#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

failure_bin=$test_root/failure-bin
mkdir -p "$failure_bin"
for phase in backup link selection; do
  test_home=$test_root/failure-$phase-home
  mkdir -p "$test_home"
  printf 'baseline\n' >"$test_home/.bashrc"
  chmod 0640 "$test_home/.bashrc"
  if [[ $phase == selection ]]; then run_manager install "$artifact_one" >/dev/null; fi
  cat >"$failure_bin/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source_path=${@: -2:1}
destination=${!#}
case $FIXTURE_FAIL_PHASE in
  backup) [[ $destination != "$HOME/.bashrc.before-dotfiles-release" ]] || exit 91 ;;
  link) [[ $destination != "$HOME/.bashrc" || $source_path != */.dotfiles-release-link.* ]] || exit 92 ;;
  selection) [[ $destination != "$HOME/dotfiles-releases/current" ]] || exit 93 ;;
esac
exec /usr/bin/mv "$@"
EOF
  chmod 0755 "$failure_bin/mv"
  artifact=$artifact_one
  [[ $phase != selection ]] || artifact=$artifact_two
  status=0
  FIXTURE_FAIL_PHASE=$phase PATH="$failure_bin:/usr/bin:/bin" \
    run_manager install "$artifact" >"$test_root/$phase.log" 2>&1 || status=$?
  [[ $status != 0 && $(<"$test_root/$phase.log") != *': installed and selected '* ]] ||
    fail "$phase failure reported success"
  if [[ $phase == selection ]]; then
    assert_link "$test_home/dotfiles-releases/current" "$id_one"
    [[ ! -e $test_home/dotfiles-releases/$id_two && ! -e $test_home/bin ]] ||
      fail 'failed selection retained a candidate or touched user bin'
  else
    [[ $(<"$test_home/.bashrc") == baseline &&
      $(stat -c %a "$test_home/.bashrc") == 640 &&
      ! -e $test_home/.bashrc.before-dotfiles-release &&
      ! -e $test_home/dotfiles-releases/$id_one &&
      ! -L $test_home/dotfiles-releases/current && ! -e $test_home/bin ]] ||
      fail "$phase failure did not restore the original paths"
  fi
  unlink "$failure_bin/mv"
  run_manager install "$artifact" >/dev/null
  run_manager uninstall >/dev/null
done

test_home=$test_root/restore-failure-home
mkdir -p "$test_home"
printf 'restore baseline\n' >"$test_home/.bashrc"
run_manager install "$artifact_one" >/dev/null
cat >"$failure_bin/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source_path=${@: -2:1}
destination=${!#}
[[ $source_path != "$HOME/.bashrc.before-dotfiles-release" ]] || exit 94
exec /usr/bin/mv "$@"
EOF
chmod 0755 "$failure_bin/mv"
if PATH="$failure_bin:/usr/bin:/bin" run_manager uninstall >"$test_root/restore-failure.log" 2>&1; then
  fail 'failed baseline restore reported success'
fi
assert_link "$test_home/dotfiles-releases/current" "$id_one"
assert_link "$test_home/.bashrc" "$test_home/dotfiles-releases/current/dotfiles/bash/.bashrc"
[[ $(<"$test_home/.bashrc.before-dotfiles-release") == 'restore baseline' ]] ||
  fail 'failed uninstall lost its saved baseline'
unlink "$failure_bin/mv"
run_manager uninstall >/dev/null
[[ $(<"$test_home/.bashrc") == 'restore baseline' &&
  ! -e $test_home/dotfiles-releases/$id_one ]] ||
  fail 'retry did not restore and remove the active release'

printf 'dotfiles_release: publication passed\n'
