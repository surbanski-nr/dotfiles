#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
test_bin=$test_root/bin

cleanup() {
  find "$test_root" -depth -delete
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p "$test_bin"
for command_name in bash cp cut dirname find flock git grep head jq mkdir mkfifo mktemp pkill ps python3 readlink script setsid sh sleep sort timeout tmux yamllint; do
  command_path=$(command -v "$command_name")
  ln -s "$command_path" "$test_bin/$command_name"
done

if PATH="$test_bin" command -v rg >/dev/null 2>&1; then
  fail 'isolated validation PATH unexpectedly contains rg'
fi

PATH="$test_bin" /bin/bash "$repo_dir/scripts/validate" configs

syntax_repo=$test_root/syntax-repo
mkdir -p "$syntax_repo/bash" "$syntax_repo/scripts" "$syntax_repo/tests"
cp "$repo_dir/scripts/validate" "$syntax_repo/scripts/validate"
cp "$repo_dir/bash/.bashrc" "$syntax_repo/bash/.bashrc"
cp "$repo_dir/bash/.bash_profile" "$syntax_repo/bash/.bash_profile"
cp "$repo_dir/bash/.bash_aliases" "$syntax_repo/bash/.bash_aliases"
cp "$repo_dir/tests/bash_test.sh" "$syntax_repo/tests/bash_test.sh"
cp "$repo_dir/release.env" "$syntax_repo/release.env"
cp "$repo_dir/tools.env" "$syntax_repo/tools.env"
cp "$repo_dir/validation.env" "$syntax_repo/validation.env"
cp "$repo_dir/system.env" "$syntax_repo/system.env"
cp "$repo_dir/README.md" "$syntax_repo/README.md"
printf 'if then\n' >"$syntax_repo/bash/.bash_profile"
ln -s "$(command -v shellcheck)" "$test_bin/shellcheck"

set +e
syntax_output=$(
  PATH="$test_bin" VALIDATION_TOOLS_DIR="$repo_dir/.cache/validation-tools" \
    /bin/bash "$syntax_repo/scripts/validate" bash 2>&1
)
syntax_status=$?
set -e
[[ $syntax_status -ne 0 ]] || fail 'Bash syntax gate accepted an invalid later file'
[[ $syntax_output == *'bash/.bash_profile'* ]] ||
  fail 'Bash syntax failure did not identify the invalid later file'

cp "$repo_dir/bash/.bash_profile" "$syntax_repo/bash/.bash_profile"
mkdir -p "$syntax_repo/maintenance"
for document in maintenance/setup.md maintenance/tool-updates.md; do
  cat >"$syntax_repo/$document" <<'EOF'
```bash
if then
```
EOF
  set +e
  syntax_output=$(
    PATH="$test_bin" VALIDATION_TOOLS_DIR="$repo_dir/.cache/validation-tools" \
      /bin/bash "$syntax_repo/scripts/validate" bash 2>&1
  )
  syntax_status=$?
  set -e
  [[ $syntax_status -ne 0 ]] || fail "documentation gate accepted invalid Bash syntax in $document"
  [[ $syntax_output == *"$document block starting at line 2"* ]] ||
    fail 'documentation syntax failure did not identify its source block'
  rm "$syntax_repo/$document"
done

real_tmux=$(command -v tmux)
rm "$test_bin/tmux"
ln -s "$repo_dir/tests/fixtures/validation/tmux-fail-show-options" \
  "$test_bin/tmux"
tmux_log=$test_root/tmux.log

set +e
PATH="$test_bin" TEST_REAL_TMUX="$real_tmux" TEST_TMUX_LOG="$tmux_log" \
  /bin/bash "$repo_dir/scripts/validate" configs >/dev/null 2>&1
tmux_status=$?
set -e
[[ $tmux_status -eq 73 ]] || fail 'tmux failure fixture returned an unexpected status'
IFS=$'\t' read -r tmux_home tmux_socket <"$tmux_log"
[[ -n $tmux_home && ! -e $tmux_home ]] ||
  fail 'tmux validation left its temporary HOME after failure'
[[ -n $tmux_socket ]] || fail 'tmux failure fixture did not record a socket'
if "$real_tmux" -L "$tmux_socket" has-session >/dev/null 2>&1; then
  fail 'tmux validation left its private server running after failure'
fi

ln -s "$(command -v actionlint)" "$test_bin/actionlint"
ln -s "$repo_dir/tests/fixtures/validation/zizmor-offline" "$test_bin/zizmor"
zizmor_log=$test_root/zizmor.log
env -u GH_TOKEN -u GITHUB_TOKEN TEST_ZIZMOR_LOG="$zizmor_log" \
  VALIDATION_TOOLS_DIR="$test_root/empty-tools" PATH="$test_bin" \
  /bin/bash "$repo_dir/scripts/validate" workflows
grep -Fx -- '--offline --persona=pedantic --config zizmor.yml .' "$zizmor_log" \
  >/dev/null || fail 'workflow validation did not select the offline Zizmor audit'

TEST_REPO_DIR="$repo_dir" TEST_TMP="$test_root" python3 - <<'PY'
import errno
import os
from pathlib import Path
import pty
import select
import signal
import subprocess
import time

repo = Path(os.environ['TEST_REPO_DIR'])
root = Path(os.environ['TEST_TMP'])


def processes():
    output = subprocess.check_output(['ps', '-eo', 'pid=,ppid=,sid=,stat=,args='], text=True)
    return {int(fields[0]): fields[1:] for line in output.splitlines()
            if len(fields := line.split(None, 4)) == 5}


def stop_test(signum, _frame):
    raise SystemExit(128 + signum)


signal.signal(signal.SIGTERM, stop_test)


for mode in ('bash', 'configs'):
    temporary = root / ('interrupt-' + mode)
    temporary.mkdir()
    pid, terminal = pty.fork()
    if pid == 0:
        os.chdir(repo)
        os.environ.update(TMPDIR=str(temporary), TERM='xterm-256color')
        signal.signal(signal.SIGINT, signal.SIG_DFL)
        signal.signal(signal.SIGTERM, signal.SIG_DFL)
        os.execv('/bin/bash', ['bash', str(repo / 'scripts/validate'), mode])
    sessions = {pid}
    servers = set()
    output = bytearray()
    interrupted = False
    status = None
    deadline = time.monotonic() + 60
    try:
        while time.monotonic() < deadline:
            records = processes()
            children = {pid}
            while True:
                found = {child for child, row in records.items() if int(row[0]) in children}
                if found <= children:
                    break
                children.update(found)
            sessions.update(int(records[child][1]) for child in children if child in records)
            ready, _, _ = select.select([terminal], [], [], .02)
            if ready:
                try:
                    output.extend(os.read(terminal, 65536))
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
            servers.update(temporary.glob('dotfiles-eye-timer.*/socket'))
            running = (bool(servers) if mode == 'configs' else
                       any('bash tests/bash_test.sh' in records[child][3]
                           for child in children if child in records))
            if running and not interrupted:
                os.write(terminal, b'\x03')
                interrupted = True
                deadline = time.monotonic() + 10
            finished, result = os.waitpid(pid, os.WNOHANG)
            if finished:
                status = os.waitstatus_to_exitcode(result)
                break
        assert interrupted, (f'{mode}: validation did not reach the interruption check\n' +
                             output.decode(errors='replace')[-2000:])
        assert status is not None and status != 0, f'{mode}: Ctrl+C did not stop validation'
        survivors = {child: row for child, row in processes().items()
                     if int(row[1]) in sessions and not row[2].startswith('Z')}
        assert not survivors, f'{mode}: Ctrl+C left test processes: {survivors}'
        for socket in servers:
            result = subprocess.run(['tmux', '-S', str(socket), 'has-session'], timeout=3,
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            assert result.returncode != 0, 'Ctrl+C left the private timer server running'
            assert not socket.parent.exists(), 'Ctrl+C left the private timer test directory'
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        (root / ('interrupt-' + mode + '.log')).write_bytes(output)
        for socket in servers:
            subprocess.run(['tmux', '-S', str(socket), 'kill-server'], timeout=3,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for child, row in processes().items():
            if int(row[1]) in sessions and not row[2].startswith('Z'):
                try:
                    os.kill(child, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        try:
            os.waitpid(pid, 0)
        except ChildProcessError:
            pass
        os.close(terminal)
        signal.signal(signal.SIGTERM, stop_test)
PY

printf 'Validation tests passed\n'
