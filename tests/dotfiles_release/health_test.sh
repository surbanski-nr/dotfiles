#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=fixture.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/fixture.sh"
create_fixture

test_home=$test_root/empty-home
mkdir -p "$test_home"
if run_manager health >"$test_root/empty-health.log" 2>&1; then
  fail 'health accepted a host without installed releases'
fi
[[ ! -e $test_home/dotfiles-releases ]] || fail 'health created a release store'

test_home=$test_root/prerequisites-home
mkdir -p "$test_home" "$test_root/no-sort"
for executable in /usr/bin/*; do
  [[ $executable != /usr/bin/sort && -f $executable && -x $executable ]] || continue
  ln -s "$executable" "$test_root/no-sort/${executable##*/}"
done
if PATH="$test_root/no-sort" run_manager install "$artifact_one" >"$test_root/prerequisites.log" 2>&1; then
  fail 'installation accepted a missing system prerequisite'
fi
[[ $(<"$test_root/prerequisites.log") == *'required command is missing: sort'* &&
  ! -e $test_home/dotfiles-releases ]] ||
  fail 'system prerequisite failure modified HOME or omitted its cause'

test_home=$test_root/health-home
mkdir -p "$test_home/bin"
for command_name in helm rg node; do
  printf '#!/usr/bin/env bash\nexit 91\n' >"$test_home/bin/$command_name"
  chmod 0755 "$test_home/bin/$command_name"
done
PATH="$test_home/bin:$PATH" VIRTUAL_ENV="$test_home/bin" \
  run_manager install "$artifact_one" >/dev/null
home_digest=$(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  -C "$test_home" -cf - . | sha256sum)
for requested in '' "$id_one"; do
  arguments=(health)
  [[ -z $requested ]] || arguments+=("$requested")
  output=$(PATH="$test_home/bin:$PATH" VIRTUAL_ENV="$test_home/bin" \
    run_manager "${arguments[@]}")
  [[ $output == *"$id_one is healthy"* ]] || fail 'health did not report the selected release'
done
[[ $(tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  -C "$test_home" -cf - . | sha256sum) == "$home_digest" ]] ||
  fail 'health changed HOME or installed payloads'
for public_path in .config/nvim2 .local/share/nvim2 \
  .config/k9s/config.yaml .tmux/plugins/tmux-resurrect; do
  path=$test_home/$public_path
  original_target=$(readlink -- "$path")
  unlink "$path"
  for requested in '' "$id_one"; do
    arguments=(health)
    [[ -z $requested ]] || arguments+=("$requested")
    if run_manager "${arguments[@]}" >"$test_root/missing-public-link.log" 2>&1; then
      fail "health accepted missing active $public_path"
    fi
    [[ $(<"$test_root/missing-public-link.log") == *'active release link is missing or incorrect:'* &&
      ! -L $path ]] || fail 'health repaired a public link or omitted the cause'
  done
  run_manager set "$id_one" >/dev/null
  assert_link "$path" "$original_target"
done
unlink "$test_home/.gitconfig"
ln -s "dotfiles-releases/$id_one/dotfiles/git/.gitconfig" "$test_home/.gitconfig"
if run_manager health >"$test_root/pinned-public-link.log" 2>&1; then
  fail 'health accepted a public link pinned to a physical release instead of current'
fi
unlink "$test_home/.gitconfig"
printf 'private config replacement\n' >"$test_home/.gitconfig"
if run_manager health >"$test_root/replaced-public-path.log" 2>&1; then
  fail 'health accepted a replaced active config link'
fi
[[ $(<"$test_home/.gitconfig") == 'private config replacement' ]] ||
  fail 'health modified a user replacement'
unlink "$test_home/.gitconfig"
ln -s "$test_home/dotfiles-releases/current/dotfiles/git/.gitconfig" "$test_home/.gitconfig"
status=0
FIXTURE_FAIL_PYTHON_IMPORT=1 run_manager set "$id_one" >"$test_root/import-failure.log" 2>&1 || status=$?
[[ $status == 95 ]] || fail 'set accepted a failed Python import'
assert_link "$test_home/dotfiles-releases/current" "$id_one"
status=0
FIXTURE_FAIL_PYTHON_IMPORT=1 run_manager health >"$test_root/health-import-failure.log" 2>&1 || status=$?
[[ $status == 95 ]] || fail 'health accepted a failed Python import'
FIXTURE_FAIL_PYTHON_IMPORT=1 run_manager set --skip-health "$id_one" >/dev/null 2>&1

make_artifact "$commit_two" broken-health "$artifact_two" 2.0
broken_release=$test_root/stage-broken-health/$id_two
printf '#!/usr/bin/env bash\nexit 96\n' >"$broken_release/tools/bin/rg"
repack_artifact broken-health "$id_two" "$artifact_two"
run_manager verify "$artifact_two" >/dev/null
status=0
run_manager install "$artifact_two" >"$test_root/install-health-failure.log" 2>&1 || status=$?
[[ $status == 96 && ! -e $test_home/dotfiles-releases/$id_two ]] ||
  fail 'failed install health did not remove the candidate'
assert_link "$test_home/dotfiles-releases/current" "$id_one"
run_manager install --skip-health "$artifact_two" >"$test_root/skipped-health.log" 2>&1
assert_link "$test_home/dotfiles-releases/current" "$id_two"
[[ $(<"$test_root/skipped-health.log") == *'skipped runtime health checks'* ]] ||
  fail 'runtime bypass was silent'
run_manager set "$id_one" >/dev/null
for command in health set; do
  status=0
  run_manager "$command" "$id_two" >"$test_root/inactive-$command-failure.log" 2>&1 || status=$?
  [[ $status == 96 ]] || fail "$command accepted the inactive broken release"
  assert_link "$test_home/dotfiles-releases/current" "$id_one"
done
run_manager set --skip-health "$id_two" >/dev/null 2>&1
assert_link "$test_home/dotfiles-releases/current" "$id_two"
run_manager health "$id_one" >/dev/null
assert_link "$test_home/dotfiles-releases/current" "$id_two"
run_manager uninstall >/dev/null
if run_manager health >/dev/null 2>&1; then fail 'health without current selected another release'; fi
run_manager health "$id_one" >/dev/null
[[ ! -L $test_home/dotfiles-releases/current ]] || fail 'health activated the specified release'
run_manager set "$id_one" >/dev/null

release=$test_home/dotfiles-releases/$id_one
tampered=$release/config/nvim2/init.lua
printf 'tampered\n' >>"$tampered"
for command in health set; do
  if run_manager "$command" "$id_one" >/dev/null 2>&1; then fail "$command accepted modified content"; fi
done
if run_manager set --skip-health "$id_one" >/dev/null 2>&1; then
  fail 'runtime bypass accepted modified content'
fi
if run_manager install --skip-health "$artifact_one" >/dev/null 2>&1; then
  fail 'runtime bypass reused an installed release with modified content'
fi
printf 'fixture one\n' >"$tampered"
original_mode=$(stat -c %a "$tampered")
chmod 0600 "$tampered"
if run_manager set "$id_one" >/dev/null 2>&1; then fail 'set accepted a modified mode'; fi
chmod "$original_mode" "$tampered"
release_link="$release/config/nvim2/tests/Lua 5.4 zh-cn utf8/link with space"
unlink "$release_link"
ln -s '../../init.lua' "$release_link"
if run_manager set "$id_one" >/dev/null 2>&1; then fail 'set accepted a modified symlink'; fi
unlink "$release_link"
ln -s 'target file' "$release_link"
printf 'unlisted\n' >"$release/unlisted"
if run_manager set "$id_one" >/dev/null 2>&1; then fail 'set accepted an unrecorded file'; fi
unlink "$release/unlisted"
run_manager set "$id_one" >/dev/null

checker="$repo_dir/scripts/check-dotfiles-release"
tty_release=$test_root/'Nvim release with spaces'
tty_home=$test_root/'Nvim health home with spaces'
mkdir -p "$tty_release/config/nvim2/tests" "$tty_home"
cat >"$tty_release/config/nvim2/tests/check.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ ! -t 0 ]]
timeout --signal=TERM --kill-after=1s 1s bash --noprofile --norc -ic \
  'printf "nvim-tty-health-ok\n"'
if flock -n "$FIXTURE_NVIM_LOCK" true; then exit 95; fi
sleep 30 </dev/null >/dev/null 2>&1 &
printf '%s\n' "$!" >"$FIXTURE_NVIM_CHILD_PID"
exit "${FIXTURE_NVIM_STATUS:-0}"
EOF
TEST_CHECKER="$checker" TEST_NVIM_RELEASE="$tty_release" TEST_NVIM_HOME="$tty_home" python3 - <<'PY'
import errno
import os
import pty
import select
import signal
import subprocess
import time

checker = os.environ['TEST_CHECKER']
release = os.environ['TEST_NVIM_RELEASE']
home = os.environ['TEST_NVIM_HOME']
for expected in (0, 94):
    lock = os.path.join(home, f'manager-{expected}.lock')
    child_pid_file = os.path.join(home, f'health-child-{expected}.pid')
    with open(lock, 'w'):
        pass
    pid, terminal = pty.fork()
    if pid == 0:
        os.environ['FIXTURE_NVIM_STATUS'] = str(expected)
        os.environ['FIXTURE_NVIM_LOCK'] = lock
        os.environ['FIXTURE_NVIM_CHILD_PID'] = child_pid_file
        os.execl('/bin/bash', 'bash', '-c',
                 'source "$1"; exec {LOCK_FD}<"$4"; flock -x "$LOCK_FD"; '
                 'health_stage Nvim health_nvim "$2" "$3"',
                 'nvim-health-test', checker, release, home, lock)
    output = bytearray()
    status = None
    try:
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            ready, _, _ = select.select([terminal], [], [], .02)
            if ready:
                try:
                    output.extend(os.read(terminal, 65536))
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
            finished, result = os.waitpid(pid, os.WNOHANG)
            if finished:
                status = os.waitstatus_to_exitcode(result)
                break
        decoded = output.decode(errors='replace')
        assert status == expected, (status, expected, decoded)
        assert 'nvim-tty-health-ok' in decoded, decoded
        if expected:
            assert f'Nvim health check failed (status {expected})' in decoded, decoded
        probe = subprocess.run(['flock', '-n', lock, 'true'], timeout=5)
        assert probe.returncode == 0, 'Nvim descendant retained the lock'
    finally:
        if status is None:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            os.waitpid(pid, 0)
        if os.path.exists(child_pid_file):
            with open(child_pid_file) as pid_file:
                child = int(pid_file.read())
            try:
                os.kill(child, signal.SIGTERM)
            except ProcessLookupError:
                pass
        os.close(terminal)
PY

functional_release=$test_root/functional-release
mkdir -p "$functional_release/bin"
printf '#!/usr/bin/env bash\nexit 96\n' >"$functional_release/bin/rg"
chmod 0755 "$functional_release/bin/rg"
status=0
bash -c 'source "$1"; health_stage "CLI operations" health_cli_operations "$2" "$3"' \
  checker-test "$checker" "$functional_release" "$test_root/functional-home" \
  >"$test_root/functional-failure.log" 2>&1 || status=$?
[[ $status == 96 && $(<"$test_root/functional-failure.log") == *'CLI operations health check failed (status 96)'* ]] ||
  fail 'CI functional checker omitted a runtime failure'

printf 'dotfiles_release: health passed\n'
