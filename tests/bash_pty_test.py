#!/usr/bin/env python3

from collections import Counter
import errno
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


repo = Path(__file__).resolve().parents[1]


class Shell:
    def __init__(self, home, name):
        self.prompt = f'__BASH_PTY_{name}__ '.encode()
        self.log = home / f'prompt-{name}.log'
        self.buffer = bytearray()
        self.transcript = bytearray()
        environment = {
            'HOME': str(home), 'PATH': '/usr/bin:/bin', 'TERM': 'xterm-256color',
            'LANG': 'C.UTF-8', 'TEST_COMMAND_MODE': 'terminal',
            'TEST_SHELL_NAME': name, 'TEST_PROMPT_LOG': str(self.log),
            'TEST_EXIT_LOG': str(home / f'exit-{name}.log'),
            'TEST_FZF_SELECTION': 'printf "fzf-selection-works\\n"',
        }
        self.pid, self.terminal = pty.fork()
        if self.pid == 0:
            try:
                os.chdir(home)
                os.execve('/bin/bash', ['bash', '--noprofile', '--rcfile',
                                       str(home / '.bashrc'), '-i'], environment)
            except BaseException as error:
                os.write(2, f'cannot start Bash: {error}\n'.encode())
                os._exit(127)
        try:
            fcntl.ioctl(self.terminal, termios.TIOCSWINSZ,
                        struct.pack('HHHH', 24, 160, 0, 0))
        except BaseException:
            self.close()
            raise

    def __enter__(self):
        try:
            self.expect(self.prompt)
            self.check_warnings()
            return self
        except BaseException:
            self.close()
            raise

    def __exit__(self, *_):
        self.close()

    def read(self, delay):
        if select.select([self.terminal], [], [], delay)[0]:
            try:
                data = os.read(self.terminal, 65536)
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                return False
            self.buffer.extend(data)
            self.transcript.extend(data)
            # Readline redraws include CSI controls and carriage returns. Keep
            # the raw transcript for diagnostics, but match complete output lines.
            self.buffer[:] = re.sub(rb'\x1b\[[0-?]*[ -/]*[@-~]', b'', self.buffer)
            self.buffer[:] = self.buffer.replace(b'\r\n', b'\n').replace(b'\r', b'')
            return bool(data)
        return True

    def expect(self, marker):
        deadline = time.monotonic() + 10
        while marker not in self.buffer:
            if time.monotonic() >= deadline or not self.read(.05):
                raise AssertionError(f'missing {marker!r}:\n' +
                                     self.transcript.decode(errors='replace')[-4000:])
        end = self.buffer.index(marker) + len(marker)
        output = bytes(self.buffer[:end])
        del self.buffer[:end]
        return output

    def send(self, keys):
        os.write(self.terminal, keys)

    def command(self, code=''):
        self.send(code.encode() + b'\r')
        return self.expect(self.prompt)

    def check_warnings(self):
        for message in (b'line editing not enabled', b'cannot set terminal process group',
                        b'no job control', b'dotfiles:'):
            assert message not in self.transcript, self.transcript.decode(errors='replace')

    def finish(self, expected=0):
        self.send(f'exit {expected}\r'.encode())
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            finished, status = os.waitpid(self.pid, os.WNOHANG)
            if finished:
                self.pid = None
                assert os.waitstatus_to_exitcode(status) == expected, status
                self.check_warnings()
                return
            self.read(.02)
        raise AssertionError('interactive Bash did not exit')

    def close(self):
        handlers = {sig: signal.signal(sig, signal.SIG_IGN)
                    for sig in (signal.SIGINT, signal.SIGTERM)}
        try:
            if self.pid is not None:
                subprocess.run(['pkill', '-HUP', '--session', str(self.pid)],
                               check=False, timeout=2)
                deadline = time.monotonic() + 1
                finished = False
                while time.monotonic() < deadline:
                    if os.waitpid(self.pid, os.WNOHANG)[0]:
                        finished = True
                        break
                    time.sleep(.02)
                # Bash can exit while a child ignores HUP and keeps running.
                subprocess.run(['pkill', '-KILL', '--session', str(self.pid)],
                               check=False, timeout=2)
                if not finished:
                    os.waitpid(self.pid, 0)
                self.pid = None
        finally:
            os.close(self.terminal)
            for sig, handler in handlers.items():
                signal.signal(sig, handler)


def prepare_home(home, packaged=False):
    home.mkdir()
    commands = home / 'bin'
    commands.mkdir()
    for command in ('clear', 'fzf', 'zoxide', 'oh-my-posh'):
        (commands / command).symlink_to(repo / 'tests/fixtures/bash/command')
    (home / '.oh-my-posh.omp.json').symlink_to(repo / 'oh-my-posh/.oh-my-posh.omp.json')
    (home / '.extras').write_text(
        'PS1="__BASH_PTY_${TEST_SHELL_NAME}__ "\n'
        'PROMPT_COMMAND+=(\'printf "user\\n" >>"$TEST_PROMPT_LOG"\')\n'
        'trap \'printf "%s\\n" "$?" >>"$TEST_EXIT_LOG"\' EXIT\n'
    )
    source = repo
    if packaged:
        release = home / 'dotfiles-releases/dotfiles-aaaaaaaaaaaa'
        source = release / 'dotfiles'
        for file in ('bash/.bashrc', 'bash/.bash_history_lib', 'scripts/bash-history-archive'):
            destination = source / file
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(repo / file, destination)
        (release.parent / 'current').symlink_to(release.name)
        source = release.parent / 'current/dotfiles'
    (home / '.bashrc').symlink_to(source / 'bash/.bashrc')


def check_keyboard(home):
    prepare_home(home)
    with Shell(home, 'keyboard') as shell:
        output = shell.command(
            '[[ -t 0 && -t 1 && -t 2 && -o monitor && -o emacs ]] && '
            'printf "terminal-ready\\n"')
        assert b'\nterminal-ready\n' in output, output
        for reload in (False, True):
            if reload:
                shell.command('source ~/.bashrc; source ~/.bashrc')
            shell.send(b'printf "line-kept\\n"\x0c')
            shell.expect(b'\n__BOUND_CLEAR__\n')
            shell.send(b'\r')
            shell.expect(b'\nline-kept\n')
            shell.expect(shell.prompt)
            shell.send(b'wrong-command\x12\r')
            shell.expect(b'\nfzf-selection-works\n')
            shell.expect(shell.prompt)
        shell.finish()
    print('Bash PTY: keyboard bindings and reload passed')


def check_shared_history(home):
    prepare_home(home, packaged=True)
    with Shell(home, 'first') as first, Shell(home, 'second') as second:
        first.command('printf "from-first-one\\n"')
        second.command()
        second.send(b'\x1b[A\r')
        second.expect(b'\nfrom-first-one\n')
        second.expect(second.prompt)
        second.command('printf "from-second-one\\n"')
        first.command()
        first.send(b'\x10\r')
        first.expect(b'\nfrom-second-one\n')
        first.expect(first.prompt)
        for shell, name in ((first, 'first'), (second, 'second')):
            shell.command(f'printf "from-{name}-two\\n"')
            before = Counter(shell.log.read_text().splitlines())
            shell.command('source ~/.bashrc; source ~/.bashrc; source ~/.bashrc')
            after = Counter(shell.log.read_text().splitlines())
            assert after - before == Counter(user=1, zoxide=1, posh=1), (before, after)
        first.finish(17)
        second.finish()
    entries = Counter((home / '.histfile').read_text().splitlines())
    # Up/Ctrl-P repeat the latest imported entry. ignoredups omits that
    # consecutive repetition; every distinct command must be saved once.
    for name in ('first', 'second'):
        for round in ('one', 'two'):
            assert entries[f'printf "from-{name}-{round}\\n"'] == 1, entries
    assert entries['exit 17'] == 1 and entries['exit 0'] == 1, entries
    assert (home / 'exit-first.log').read_text() == '17\n'
    assert (home / 'exit-second.log').read_text() == '0\n'
    print('Bash PTY: cross-shell recall, prompt hooks and EXIT preservation passed')


def check_live_archiving(home):
    prepare_home(home)
    (home / '.histfile').write_text(''.join(f': archived-seed-{i:06d}\n' for i in range(89999)))
    with Shell(home, 'archiver') as first, Shell(home, 'stale-peer') as second:
        first.command('printf "archive-trigger-command\\n"')
        # Advance the periodic trigger without sleeping five minutes. Bash still
        # performs the check automatically through its real prompt loop.
        first.command('_DOTFILES_HISTORY_NEXT_CHECK=$SECONDS')
        second.command('printf "peer-after-archive\\n"')
        first.finish()
        second.finish()
    entries = (home / '.histfile').read_text().splitlines()
    assert sum(line.startswith(': archived-seed-') for line in entries) == 9999
    assert ': archived-seed-000000' not in entries
    for command in ('printf "archive-trigger-command\\n"', 'printf "peer-after-archive\\n"'):
        assert entries.count(command) == 1, command
    archives = list((home / '.histfile.d').glob('history-*.hist'))
    assert len(archives) == 1, archives
    assert sum(line.startswith(': archived-seed-')
               for line in archives[0].read_text().splitlines()) == 80000
    print('Bash PTY: automatic archiving with another open shell passed')


def stop_test(signum, _frame):
    raise SystemExit(128 + signum)


if __name__ == '__main__':
    signal.signal(signal.SIGTERM, stop_test)
    signal.signal(signal.SIGINT, stop_test)
    with tempfile.TemporaryDirectory(prefix='dotfiles-bash-pty.') as directory:
        root = Path(directory)
        check_keyboard(root / 'keyboard home')
        check_shared_history(root / 'shared release home')
        check_live_archiving(root / 'archiving home')
    print('Bash PTY tests passed')
