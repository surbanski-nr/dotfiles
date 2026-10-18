#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export TEST_REPO_DIR=$repo_dir

python3 - <<'PY'
import fcntl
import os
from pathlib import Path
import pty
import re
import select
import shutil
import signal
import struct
import subprocess
import tempfile
import termios
import time

repo = Path(os.environ['TEST_REPO_DIR'])
timer = repo / 'tmux/.tmux/eye-timer.sh'
root = Path(tempfile.mkdtemp(prefix='dotfiles-eye-timer.'))
socket = str(root / 'socket')
command = ['tmux', '-S', socket]
clients = []
clock = rb'\d{2}:\d{2} \d{2}-.{3}-\d{2}'


def tmux(*args):
    return subprocess.check_output(command + list(args), text=True, timeout=5).strip()


def run(*args):
    return subprocess.check_output(['bash', str(timer), socket, *args], text=True, timeout=5)


def option(name):
    return tmux('show-options', '-gqv', '@eye-timer-' + name)


def wait_until(check, message, timeout=3):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if check():
            return
        time.sleep(.02)
    raise AssertionError(message)


def read_terminal(master, duration=.15):
    output = bytearray()
    end = time.monotonic() + duration
    while time.monotonic() < end:
        ready, _, _ = select.select([master], [], [], max(0, end - time.monotonic()))
        if ready:
            output.extend(os.read(master, 65536))
    return bytes(output)


def attach(width, terminal=None):
    master, slave = pty.openpty() if terminal is None else tuple(map(os.dup, terminal))
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, width, 0, 0))
    process = subprocess.Popen(command + ['attach-session', '-t', 'timer'],
                               stdin=slave, stdout=slave, stderr=slave,
                               start_new_session=True,
                               env={**os.environ, 'TERM': 'xterm-256color', 'TMUX': ''})
    clients.append((master, slave, process))
    read_terminal(master)
    return master


def choose(master, key):
    os.write(master, b'\x01t')
    output = read_terminal(master)
    assert b'Eye break timer' in output, 'Ctrl+a t did not open the timer menu'
    os.write(master, key)
    read_terminal(master)


def stop_test(signum, _frame):
    raise SystemExit(128 + signum)


signal.signal(signal.SIGTERM, stop_test)


try:
    # Exercise loading from a symlink, as bstow installs the config.
    (root / 'tmux.conf').symlink_to(repo / 'tmux/.tmux.conf')
    # Keep the status bar regression independent of the host's routes.
    (root / 'bin').mkdir()
    ip = root / 'bin/ip'
    ip.write_text("#!/bin/sh\nprintf '%s\\n' '1.1.1.1 dev test0 src 192.0.2.1'\n")
    ip.chmod(0o755)
    environment = {**os.environ, 'HOME': str(root), 'TMUX': '',
                   'PATH': str(ip.parent) + ':' + os.environ['PATH'],
                   'TMUX_OFFLINE_RELEASE_ROOT': '', 'TMUX_PLUGIN_MANAGER_PATH': ''}
    pane_command = 'bash -c \'while IFS= read -r line; do printf "PANE_INPUT=%s\\n" "$line"; done\''
    subprocess.run(command + ['-f', str(root / 'tmux.conf'), 'new-session', '-d',
                              '-s', 'timer', '-n', 'work', pane_command],
                   env=environment, check=True, timeout=5)
    wait_until(lambda: option('state') == 'off', 'timer did not initialize')
    tmux('set-option', '-g', 'status-interval', '5')
    master = attach(148)
    client = tmux('list-clients', '-F', '#{client_name}').splitlines()[0]
    # A second attach from the same terminal leaves the suspended client name ambiguous.
    suspended = clients[-1][2]
    tmux('suspend-client', '-t', client)
    os.kill(suspended.pid, signal.SIGSTOP)
    master = attach(148, clients[-1][:2])

    choose(master, b's')
    assert run('status') in ('60:00', '59:59'), 'default timer is not 60 minutes'
    tmux('refresh-client')
    output = read_terminal(master)
    pattern = rb'(?:60:00|59:59) \| 192\.0\.2\.1 \| ' + clock
    assert re.search(pattern, output), 'timer hid IP/time/date on a wide terminal: ' + repr(output)
    deadline = int(option('deadline'))
    run('start')
    assert int(option('deadline')) == deadline, 'Start restarted a running timer'

    choose(master, b'm')
    os.write(master, b'12\r')
    wait_until(lambda: option('minutes') == '12', 'menu did not set the minutes')
    assert run('status') == '12:00', 'setting minutes did not leave the timer ready'
    assert tmux('capture-pane', '-p') == '', 'confirming minutes sent Enter to the pane'
    tmux('detach-client', '-t', client)
    os.kill(suspended.pid, signal.SIGCONT)
    suspended.wait(timeout=3)
    for invalid in ('0', '1441', 'abc'):
        result = subprocess.run(['bash', str(timer), socket, 'set-minutes', invalid],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
        assert result.returncode == 2 and option('minutes') == '12', 'invalid minutes were accepted'
    choose(master, b'm')
    os.write(master, ('1; touch "' + str(root / 'injected') + '"\r').encode())
    read_terminal(master)
    wait_until(lambda: tmux('display-message', '-p', '#{pane_in_mode}') == '1',
               'invalid prompt did not display its error')
    assert option('minutes') == '12', 'editable prompt accepted invalid minutes'
    assert not (root / 'injected').exists(), 'timer executed invalid input'
    os.write(master, b'q')
    read_terminal(master)

    choose(master, b's')
    # Advance elapsed time without slowing the suite with a real minute-long wait.
    tmux('set-option', '-g', '@eye-timer-deadline', str(int(time.time()) + 42))
    choose(master, b'p')
    paused = run('status')
    assert paused.startswith('|| 00:4'), 'pause did not retain the remaining time'
    time.sleep(1.1)
    assert run('status') == paused, 'paused timer kept counting down'
    choose(master, b's')
    assert 38 <= int(option('deadline')) - time.time() <= 42, 'resume restarted the full duration'

    tmux('source-file', str(root / 'tmux.conf'))
    assert option('state') == 'running', 'config reload stopped the timer'
    tmux('set-option', '-g', '@eye-timer-deadline', str(int(time.time()) - 1))
    jobs = [subprocess.Popen(['bash', str(timer), socket, 'status'], stdout=subprocess.PIPE)
            for _ in range(4)]
    for job in jobs:
        output, _ = job.communicate(timeout=5)
        assert job.returncode == 0 and output == b'', 'expired timer retained a label'
    assert option('state') == 'done', 'expired timer did not finish'
    tmux('refresh-client', '-t', client)
    output = read_terminal(master)
    assert b'48;2;185;28;28' in output and b'38;2;255;255;255' in output, 'completed timer did not show a red bar with white text'
    assert b'BREAK' not in output and re.search(clock, output), 'completion hid the clock/date or added a label'

    choose(master, b'r')
    assert run('status') == '12:00', 'Reset did not restore the configured duration'
    assert tmux('display-message', '-p', '#{E:status-style}') == 'bg=#008080,fg=#ffffff'
    narrow = attach(30)
    tmux('refresh-client')
    output = read_terminal(narrow)
    assert b'12:00' in output, 'narrow terminal hid the timer'
    narrow_client = tmux('list-clients', '-F', '#{client_name}').splitlines()[-1]
    fields = tmux('display-message', '-c', narrow_client, '-p',
                  '#{E:@dotfiles-status-network}#{T:@dotfiles-status-clock}')
    assert fields == '', 'narrow terminal did not give the timer priority'

    choose(master, b'o')
    assert run('status') == '', 'Off did not hide the timer'
    assert tmux('show-options', '-gv', 'status-interval') == '5', 'timer changed the status refresh interval'
    print('Tmux eye timer tests passed')
finally:
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    subprocess.run(command + ['kill-server'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
    for master, slave, process in clients:
        if process.poll() is None:
            os.kill(process.pid, signal.SIGCONT)
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)
        os.close(master)
        os.close(slave)
    shutil.rmtree(root)
PY
