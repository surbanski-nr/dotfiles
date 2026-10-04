# Dotfiles

Personal Bash, Git, tmux, Nvim2, Midnight Commander, Oh My Posh, k9s and
Codex configuration for Linux x86-64. The qualified targets are Debian 13,
Ubuntu 24.04, Ubuntu 26.04 and Amazon Linux 2023.

## Setup

The complete connected and restricted procedures, exact tool ownership,
archive layout and private input files are in [SETUP.md](SETUP.md).

On a connected machine, run the reviewed entry points as the intended ordinary
user. Only `setup-system` uses `sudo`:

```bash
./setup-system
./setup-tools
./setup-asdf

for file in "$HOME/.bash_profile" "$HOME/.bashrc"; do
  if [[ -f $file && ! -L $file && ! -e $file.before-dotfiles && ! -L $file.before-dotfiles ]]; then
    mv -- "$file" "$file.before-dotfiles"
  fi
done
./bstow --dry-run -v -t "$HOME" stow \
  git tmux bash mc oh-my-posh k9s nvim2 gnupg codex
./bstow -v -t "$HOME" stow \
  git tmux bash mc oh-my-posh k9s nvim2 gnupg codex

source "$HOME/.bashrc"
hash -r
dotfiles-check
```

`bstow` manages package files as individual links, records package ownership
under `$HOME/.local/state/bstow`, and protects regular files and foreign links.
Use `restow` after pulling deletions or renames. Preview `--force` before using
it to adopt links from an older checkout.

The setup sequence moves regular distribution-provided Bash startup files
aside without overwriting an existing backup. `bstow --dry-run` reports any
remaining conflict, including a foreign symlink.

Existing Homebrew installations and private shell configuration are left
alone. Setup does not install Homebrew or initialize it from Bash.

Release data is explicit: `versions.env` contains ordered
`version|full_URL|SHA256` records for daily tools and project runtimes, while
`validation.env` owns validator records, including the only Task pin. The
first record is the default. `ASDF_PLUGINS` separately pins plugin repositories
and commits; asdf keeps responsibility for fetching and verifying its plugins.
The tmux plugin `*_REPO` and `*_COMMIT` pairs also live in `versions.env`.

The Kubernetes prompt segment is disabled by default. Run `kp` to toggle it
for the current shell session. While disabled, Oh My Posh does not read the
kubeconfig for that segment.

## Nvim2

The active editor profile uses Neovim 0.12.5 or newer, built-in `vim.pack`, a
generated plugin lock and explicitly pinned external tools. Start it with:

```bash
NVIM_APPNAME=nvim2 nvim
```

See the [Nvim2 guide](nvim2/.config/nvim2/README.md) for normal use and clean
rebuilds. The [offline release runbook](nvim2/.config/nvim2/offline-releases.md)
covers connected builds, restricted installation and whole-dotfiles rollback.

`v` starts Nvim2. The shell configuration does not redefine `cat`, `vi` or
`vim`, so the system editors remain independent. `old-nvim` is an unsupported
archived profile and is not installed by the normal setup.

## Updates and rollback

[TOOL_UPDATES.md](TOOL_UPDATES.md) describes disposable upgrade candidates,
Python lock regeneration, health evidence, retained version rollback and
prompt behavior. Release publication remains a separate explicit action.

Complete offline releases recover interrupted install, selection and baseline
restore operations automatically when the next manager command starts. Do not
edit the recovery journal, selection links or adjacent baseline backups by
hand. See the offline runbook before resolving a reported ownership conflict.

## Validation

Bootstrap the pinned Task executable and run every repository check with:

```bash
bash scripts/install-validation-tool task
.cache/validation-tools/bin/task validate
```

Workflow validation runs locally without GitHub credentials. Set `GH_TOKEN`,
`GITHUB_TOKEN` or use an active `gh` login to additionally enable Zizmor's
online audits. The GitHub Actions workflow supplies its repository token.

Focused tasks include `validate:bash`, `validate:configs`, `validate:nvim2`,
`validate:old-nvim`, `validate:repo`, `validate:scripts` and
`validate:workflows`.
