#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

failure_bin=$test_root/failure-bin
mkdir -p "$failure_bin"

test_home=$test_root/ownership-write-failure-home
mkdir -p "$test_home"
printf 'ownership baseline\n' >"$test_home/.bashrc"
cat >"$failure_bin/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
destination=${!#}
if [[ $destination == */.state/ownership.tsv ]]; then exit 91; fi
exec /usr/bin/mv "$@"
EOF
chmod 0755 "$failure_bin/mv"
set +e
ownership_failure_output=$(PATH="$failure_bin:/usr/bin:/bin" run_manager install "$artifact_one" 2>&1)
ownership_failure_status=$?
set -e
[[ $ownership_failure_status -ne 0 && $ownership_failure_output != *': installed '* ]] ||
  fail 'ownership write failure reported installation success'
[[ $(<"$test_home/.bashrc") == 'ownership baseline' &&
  ! -e $test_home/dotfiles-releases/current &&
  ! -e $test_home/dotfiles-releases/.state/pending.env &&
  ! -e $test_home/dotfiles-releases/$id_one ]] ||
  fail 'ownership write failure did not restore the first-install baseline'
rm "$failure_bin/mv"
run_manager install "$artifact_one" >/dev/null
run_manager uninstall >/dev/null

test_home=$test_root/pending-write-failure-home
mkdir -p "$test_home"
printf 'pending baseline\n' >"$test_home/.bashrc"
cat >"$failure_bin/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
destination=${!#}
if [[ $destination == */.state/pending.env ]]; then exit 97; fi
exec /usr/bin/mv "$@"
EOF
chmod 0755 "$failure_bin/mv"
set +e
pending_failure_output=$(PATH="$failure_bin:/usr/bin:/bin" run_manager install "$artifact_one" 2>&1)
pending_failure_status=$?
set -e
[[ $pending_failure_status -ne 0 && $pending_failure_output != *': installed '* ]] ||
  fail 'pending write failure reported installation success'
[[ $(<"$test_home/.bashrc") == 'pending baseline' &&
  ! -e $test_home/dotfiles-releases/current &&
  ! -e $test_home/dotfiles-releases/.state/pending.env &&
  ! -e $test_home/dotfiles-releases/$id_one ]] ||
  fail 'pending write failure changed the first-install baseline'
rm "$failure_bin/mv"
run_manager install "$artifact_one" >/dev/null
run_manager uninstall >/dev/null

test_home=$test_root/link-failure-home
mkdir -p "$test_home"
printf 'link baseline\n' >"$test_home/.bashrc"
cat >"$failure_bin/ln" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
destination=${!#}
if [[ $destination == */.dotfiles-release-link.* ]]; then exit 92; fi
exec /usr/bin/ln "$@"
EOF
chmod 0755 "$failure_bin/ln"
set +e
link_failure_output=$(PATH="$failure_bin:/usr/bin:/bin" run_manager install "$artifact_one" 2>&1)
link_failure_status=$?
set -e
[[ $link_failure_status -ne 0 && $link_failure_output != *': installed '* ]] ||
  fail 'managed-link failure reported installation success'
[[ $(<"$test_home/.bashrc") == 'link baseline' &&
  ! -e $test_home/dotfiles-releases/current &&
  ! -e $test_home/dotfiles-releases/.state/pending.env &&
  ! -e $test_home/dotfiles-releases/$id_one ]] ||
  fail 'managed-link failure did not restore the first-install baseline'
rm "$failure_bin/ln"
run_manager install "$artifact_one" >/dev/null
run_manager uninstall >/dev/null

test_home=$test_root/selection-failure-home
mkdir -p "$test_home"
printf 'selection baseline\n' >"$test_home/.bashrc"
run_manager install "$artifact_one" >/dev/null
cat >"$failure_bin/mv" <<EOF
#!/usr/bin/env bash
set -euo pipefail
destination=\${!#}
if [[ \$destination == '$test_home/dotfiles-releases/current' ]]; then exit 93; fi
exec /usr/bin/mv "\$@"
EOF
chmod 0755 "$failure_bin/mv"
set +e
selection_failure_output=$(PATH="$failure_bin:/usr/bin:/bin" run_manager install "$artifact_two" 2>&1)
selection_failure_status=$?
set -e
[[ $selection_failure_status -ne 0 && $selection_failure_output != *': installed '* ]] ||
  fail 'current selection failure reported installation success'
assert_link "$test_home/dotfiles-releases/current" "$id_one"
[[ ! -e $test_home/dotfiles-releases/previous &&
  ! -e $test_home/dotfiles-releases/.state/pending.env &&
  ! -e $test_home/dotfiles-releases/$id_two ]] ||
  fail 'current selection failure did not restore the A selection pair'
rm "$failure_bin/mv"
run_manager install "$artifact_two" >/dev/null
assert_link "$test_home/dotfiles-releases/current" "$id_two"
run_manager uninstall >/dev/null

test_home=$test_root/previous-selection-failure-home
mkdir -p "$test_home"
printf 'previous selection baseline\n' >"$test_home/.bashrc"
run_manager install "$artifact_one" >/dev/null
cat >"$failure_bin/mv" <<EOF
#!/usr/bin/env bash
set -euo pipefail
destination=\${!#}
if [[ \$destination == '$test_home/dotfiles-releases/previous' ]]; then exit 98; fi
exec /usr/bin/mv "\$@"
EOF
chmod 0755 "$failure_bin/mv"
set +e
previous_failure_output=$(PATH="$failure_bin:/usr/bin:/bin" run_manager install "$artifact_two" 2>&1)
previous_failure_status=$?
set -e
[[ $previous_failure_status -ne 0 && $previous_failure_output != *': installed '* ]] ||
  fail 'previous selection failure reported installation success'
assert_link "$test_home/dotfiles-releases/current" "$id_one"
[[ ! -e $test_home/dotfiles-releases/previous &&
  ! -e $test_home/dotfiles-releases/.state/pending.env &&
  ! -e $test_home/dotfiles-releases/$id_two ]] ||
  fail 'previous selection failure did not restore the A selection pair'
rm "$failure_bin/mv"
run_manager install "$artifact_two" >/dev/null
run_manager uninstall >/dev/null

test_home=$test_root/recovery-failure-home
mkdir -p "$test_home"
printf 'recovery baseline\n' >"$test_home/.bashrc"
run_manager install "$artifact_one" >/dev/null
cat >"$failure_bin/mv" <<EOF
#!/usr/bin/env bash
set -euo pipefail
destination=\${!#}
if [[ \$destination == '$test_home/dotfiles-releases/current' ]]; then exit 95; fi
exec /usr/bin/mv "\$@"
EOF
cat >"$failure_bin/unlink" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ \${!#} == '$test_home/dotfiles-releases/previous' ]]; then exit 96; fi
exec /usr/bin/unlink "\$@"
EOF
chmod 0755 "$failure_bin/mv" "$failure_bin/unlink"
set +e
recovery_failure_output=$(PATH="$failure_bin:/usr/bin:/bin" run_manager install "$artifact_two" 2>&1)
recovery_failure_status=$?
set -e
[[ $recovery_failure_status -ne 0 &&
  $recovery_failure_output == *'automatic recovery also failed'* &&
  $recovery_failure_output != *': installed '* ]] ||
  fail 'activation plus recovery failure was not reported'
assert_link "$test_home/dotfiles-releases/current" "$id_one"
[[ -f $test_home/dotfiles-releases/.state/pending.env &&
  -d $test_home/dotfiles-releases/$id_two ]] ||
  fail 'failed automatic recovery discarded its journal or retained payload'
rm "$failure_bin/mv" "$failure_bin/unlink"
run_manager install "$artifact_two" >/dev/null
assert_link "$test_home/dotfiles-releases/current" "$id_two"
[[ ! -e $test_home/dotfiles-releases/.state/pending.env ]] ||
  fail 'retry did not clear the recovered activation journal'
run_manager uninstall >/dev/null

printf 'dotfiles_release: publication passed\n'
