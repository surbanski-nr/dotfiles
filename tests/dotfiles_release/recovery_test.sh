#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

failure_bin=$test_root/failure-bin
mkdir -p "$failure_bin"

test_home=$test_root/kill-after-backup-home
mkdir -p "$test_home"
printf 'kill backup baseline\n' >"$test_home/.bashrc"
chmod 0640 "$test_home/.bashrc"
kill_backup_digest=$(sha256sum "$test_home/.bashrc")
kill_backup_mode=$(stat -c %a "$test_home/.bashrc")
cat >"$failure_bin/mv" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source_path=\${@: -2:1}
destination=\${!#}
/usr/bin/mv "\$@"
if [[ \$source_path == '$test_home/.bashrc' &&
  \$destination == '$test_home/.dotfiles-release-backup-'* ]]; then
  kill -KILL "\$PPID"
fi
EOF
chmod 0755 "$failure_bin/mv"
set +e
PATH="$failure_bin:/usr/bin:/bin" run_manager install "$artifact_one" >/dev/null 2>&1
kill_backup_status=$?
set -e
[[ $kill_backup_status -ne 0 &&
  -f $test_home/dotfiles-releases/.state/pending.env ]] ||
  fail 'SIGKILL after backup move did not leave a recovery journal'
rm "$failure_bin/mv"
run_manager install "$artifact_one" >/dev/null
run_manager uninstall >/dev/null
[[ $(sha256sum "$test_home/.bashrc") == "$kill_backup_digest" &&
  $(stat -c %a "$test_home/.bashrc") == "$kill_backup_mode" ]] ||
  fail 'retry after backup SIGKILL did not restore baseline bytes and mode'
[[ -z $(find "$test_home" -name '.dotfiles-release-backup-*' -print -quit) ]] ||
  fail 'retry after backup SIGKILL left an orphaned backup'

test_home=$test_root/kill-after-link-home
mkdir -p "$test_home"
printf 'kill link baseline\n' >"$test_home/.bashrc"
kill_link_digest=$(sha256sum "$test_home/.bashrc")
cat >"$failure_bin/mv" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source_path=\${@: -2:1}
destination=\${!#}
/usr/bin/mv "\$@"
if [[ \$source_path == '$test_home/.dotfiles-release-link.'* &&
  \$destination == '$test_home/.bashrc' ]]; then
  kill -KILL "\$PPID"
fi
EOF
chmod 0755 "$failure_bin/mv"
set +e
PATH="$failure_bin:/usr/bin:/bin" run_manager install "$artifact_one" >/dev/null 2>&1
kill_link_status=$?
set -e
[[ $kill_link_status -ne 0 && -L $test_home/.bashrc &&
  -f $test_home/dotfiles-releases/.state/pending.env ]] ||
  fail 'SIGKILL after managed-link rename did not preserve a recoverable state'
rm "$failure_bin/mv"
run_manager install "$artifact_one" >/dev/null
run_manager uninstall >/dev/null
[[ $(sha256sum "$test_home/.bashrc") == "$kill_link_digest" ]] ||
  fail 'retry after managed-link SIGKILL did not restore baseline bytes'

test_home=$test_root/kill-after-created-link-home
mkdir -p "$test_home"
cat >"$failure_bin/mv" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source_path=\${@: -2:1}
destination=\${!#}
/usr/bin/mv "\$@"
if [[ \$source_path == '$test_home/bin/.dotfiles-release-link.'* &&
  \$destination == '$test_home/bin/dotfiles-release' ]]; then
  kill -KILL "\$PPID"
fi
EOF
chmod 0755 "$failure_bin/mv"
set +e
PATH="$failure_bin:/usr/bin:/bin" run_manager install "$artifact_one" >/dev/null 2>&1
kill_created_status=$?
set -e
[[ $kill_created_status -ne 0 && -L $test_home/bin/dotfiles-release &&
  -f $test_home/dotfiles-releases/.state/pending.env ]] ||
  fail 'SIGKILL after created-link rename did not preserve a recoverable state'
rm "$failure_bin/mv"
run_manager install "$artifact_one" >/dev/null
run_manager uninstall >/dev/null
[[ ! -e $test_home/bin/dotfiles-release &&
  ! -e $test_home/dotfiles-releases/.state/pending.env ]] ||
  fail 'retry after created-link SIGKILL did not restore absence'

test_home=$test_root/kill-provider-home
mkdir -p "$test_home/bin" "$test_home/.local/state/dotfiles/setup-tools"
printf 'provider baseline\n' >"$test_home/.bashrc"
write_fake_tool "$test_home/bin/rg-0.9"
ln -s rg-0.9 "$test_home/bin/rg"
provider_content=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  -C "$test_home/bin" -cf - -- rg-0.9 | sha256sum | awk '{print $1}')
printf 'complete\t%s\t%s\n' \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  "$provider_content" >"$test_home/.local/state/dotfiles/setup-tools/rg-0.9.state"
cat >"$failure_bin/mv" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source_path=\${@: -2:1}
destination=\${!#}
/usr/bin/mv "\$@"
if [[ \$source_path == '$test_home/bin/rg' &&
  \$destination == '$test_home/bin/.dotfiles-release-backup-'* ]]; then
  kill -KILL "\$PPID"
fi
EOF
chmod 0755 "$failure_bin/mv"
set +e
PATH="$failure_bin:/usr/bin:/bin" run_manager install "$artifact_one" >/dev/null 2>&1
kill_provider_status=$?
set -e
[[ $kill_provider_status -ne 0 &&
  -f $test_home/dotfiles-releases/.state/pending.env ]] ||
  fail 'SIGKILL while migrating an owned provider link left no journal'
rm "$failure_bin/mv"
run_manager install "$artifact_one" >/dev/null
run_manager uninstall >/dev/null
assert_link "$test_home/bin/rg" rg-0.9
[[ -x $test_home/bin/rg-0.9 ]] ||
  fail 'retry after provider-link SIGKILL did not restore its payload'

test_home=$test_root/kill-selection-home
mkdir -p "$test_home"
printf 'kill selection baseline\n' >"$test_home/.bashrc"
run_manager install "$artifact_one" >/dev/null
cat >"$failure_bin/mv" <<EOF
#!/usr/bin/env bash
set -euo pipefail
destination=\${!#}
/usr/bin/mv "\$@"
if [[ \$destination == '$test_home/dotfiles-releases/current' ]]; then
  kill -KILL "\$PPID"
fi
EOF
chmod 0755 "$failure_bin/mv"
set +e
PATH="$failure_bin:/usr/bin:/bin" run_manager install "$artifact_two" >/dev/null 2>&1
kill_selection_status=$?
set -e
[[ $kill_selection_status -ne 0 &&
  -f $test_home/dotfiles-releases/.state/pending.env ]] ||
  fail 'SIGKILL after current rename did not preserve a recovery journal'
assert_link "$test_home/dotfiles-releases/current" "$id_two"
assert_link "$test_home/dotfiles-releases/previous" "$id_one"
rm "$failure_bin/mv"
run_manager install "$artifact_two" >/dev/null
assert_link "$test_home/dotfiles-releases/current" "$id_two"
assert_link "$test_home/dotfiles-releases/previous" "$id_one"
[[ ! -e $test_home/dotfiles-releases/.state/pending.env ]] ||
  fail 'retry after selection SIGKILL retained its journal'
run_manager uninstall >/dev/null

test_home=$test_root/kill-restore-home
mkdir -p "$test_home"
printf 'kill restore baseline\n' >"$test_home/.bashrc"
chmod 0640 "$test_home/.bashrc"
kill_restore_digest=$(sha256sum "$test_home/.bashrc")
kill_restore_mode=$(stat -c %a "$test_home/.bashrc")
run_manager install "$artifact_one" >/dev/null
restore_phase=$test_root/restore-recovery-phase
cat >"$failure_bin/mv" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source_path=\${@: -2:1}
destination=\${!#}
/usr/bin/mv "\$@"
if [[ \$source_path == '$test_home/.dotfiles-release-backup-'* &&
  \$destination == '$test_home/.bashrc' ]]; then
  printf 'restored\n' >'$restore_phase'
  kill -KILL "\$PPID"
fi
if [[ \$destination == '$test_home/dotfiles-releases/.state/ownership.tsv' &&
  -f '$restore_phase' && \$(<'$restore_phase') == restored ]]; then
  printf 'recorded\n' >'$restore_phase'
  kill -KILL "\$PPID"
fi
EOF
chmod 0755 "$failure_bin/mv"
set +e
PATH="$failure_bin:/usr/bin:/bin" run_manager uninstall >/dev/null 2>&1
kill_restore_status=$?
set -e
[[ $kill_restore_status -ne 0 &&
  -f $test_home/dotfiles-releases/.state/pending.env ]] ||
  fail 'SIGKILL after backup restore did not preserve its journal'
set +e
PATH="$failure_bin:/usr/bin:/bin" run_manager uninstall >/dev/null 2>&1
kill_recovery_status=$?
set -e
[[ $kill_recovery_status -ne 0 &&
  $(<"$restore_phase") == recorded &&
  -f $test_home/dotfiles-releases/.state/pending.env ]] ||
  fail 'SIGKILL during repeated recovery did not preserve its journal'
rm "$failure_bin/mv"
restore_retry_output=$(run_manager uninstall)
[[ $restore_retry_output == *'recovery already restored the pre-release baseline'* ]] ||
  fail 'retry uninstall did not report recovered baseline success'
[[ $(sha256sum "$test_home/.bashrc") == "$kill_restore_digest" &&
  $(stat -c %a "$test_home/.bashrc") == "$kill_restore_mode" ]] ||
  fail 'retry after restore SIGKILL did not preserve baseline bytes and mode'
[[ ! -e $test_home/dotfiles-releases/.state/pending.env ]] ||
  fail 'retry after restore SIGKILL retained its journal'

test_home=$test_root/kill-created-restore-home
mkdir -p "$test_home"
printf 'created restore baseline\n' >"$test_home/.bashrc"
run_manager install "$artifact_one" >/dev/null
cat >"$failure_bin/unlink" <<EOF
#!/usr/bin/env bash
set -euo pipefail
path=\${!#}
/usr/bin/unlink "\$@"
if [[ \$path == '$test_home/.bash_profile' ]]; then
  kill -KILL "\$PPID"
fi
EOF
chmod 0755 "$failure_bin/unlink"
set +e
PATH="$failure_bin:/usr/bin:/bin" run_manager uninstall >/dev/null 2>&1
kill_created_restore_status=$?
set -e
[[ $kill_created_restore_status -ne 0 && ! -e $test_home/.bash_profile &&
  -f $test_home/dotfiles-releases/.state/pending.env ]] ||
  fail 'SIGKILL after removing a created path left no recoverable state'
rm "$failure_bin/unlink"
run_manager uninstall >/dev/null
[[ ! -e $test_home/.bash_profile &&
  ! -e $test_home/dotfiles-releases/.state/pending.env ]] ||
  fail 'retry after created-path restore SIGKILL did not converge'

test_home=$test_root/foreign-restore-home
mkdir -p "$test_home"
printf 'foreign restore baseline\n' >"$test_home/.bashrc"
run_manager install "$artifact_one" >/dev/null
unlink "$test_home/.bashrc"
printf 'foreign user edit\n' >"$test_home/.bashrc"
foreign_restore_digest=$(sha256sum "$test_home/.bashrc")
set +e
foreign_restore_output=$(run_manager uninstall 2>&1)
foreign_restore_status=$?
set -e
[[ $foreign_restore_status -ne 0 &&
  $foreign_restore_output == *'refusing to replace modified managed path'* ]] ||
  fail 'foreign edit during restore was not rejected'
[[ $(sha256sum "$test_home/.bashrc") == "$foreign_restore_digest" &&
  -f $test_home/dotfiles-releases/.state/pending.env &&
  -n $(find "$test_home" -maxdepth 1 -name '.dotfiles-release-backup-*' -print -quit) ]] ||
  fail 'restore conflict changed foreign data or discarded recovery state'
unlink "$test_home/.bashrc"
ln -s "$test_home/dotfiles-releases/current/dotfiles/bash/.bashrc" "$test_home/.bashrc"
run_manager uninstall >/dev/null
[[ $(<"$test_home/.bashrc") == 'foreign restore baseline' ]] ||
  fail 'retry after repairing restore conflict did not restore baseline'

printf 'dotfiles_release: recovery passed\n'
