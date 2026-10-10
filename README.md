# Dotfiles

Personal Bash, Git, tmux, Nvim2, Midnight Commander, Oh My Posh, k9s and
Codex configuration for Linux x86-64. The qualified targets are Debian 13,
Ubuntu 24.04, Ubuntu 26.04 and Amazon Linux 2023.

## Setup

The complete connected and offline-release procedures, exact tool ownership
and private input files are in [SETUP.md](SETUP.md).

### GitHub SSH access

On the host where you will use GitHub, generate a key if you do not already
have one. Keep the private key on that host and choose a passphrase:

```bash
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
ssh-keygen -t ed25519 \
  -C "122265380+surbanski-nr@users.noreply.github.com" \
  -f "$HOME/.ssh/github"
cat "$HOME/.ssh/github.pub"
```

Do not overwrite an existing key. Add the public key to
[GitHub's SSH keys](https://github.com/settings/keys), then load the private
key into an agent for the current session. Reuse an existing agent if one
is already available:

```bash
if [[ -z ${SSH_AUTH_SOCK:-} ]]; then
  eval "$(ssh-agent -s)"
fi
ssh-add "$HOME/.ssh/github"
ssh -o IdentitiesOnly=yes -i "$HOME/.ssh/github" -T git@github.com
```

On the first connection, compare the displayed host fingerprint with
[GitHub's published SSH fingerprints](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints)
before answering `yes`. SSH then records the trusted host in
`~/.ssh/known_hosts`. Successful authentication prints a greeting but exits
with status 1 because GitHub does not provide shell access. Dotfiles startup
does not start an agent or load keys automatically.

Clone over SSH once access is verified, or use HTTPS if it is already configured:

```bash
mkdir -p "$HOME/github.com/surbanski"
git clone git@github.com:surbanski-nr/dotfiles.git "$HOME/github.com/surbanski/dotfiles"
cd "$HOME/github.com/surbanski/dotfiles"
```

### Deployment

The preferred deployment is a complete offline release, built on a connected
machine and installed without network access. Each release contains its own
tools, including every pinned kubectl and Helm version. `KUBECTL_VERSION` and
`HELM_VERSION` select a bundled client; unset or empty selects the first catalog
record. No asdf installation or shims are needed for this route.
Prepare the target's system prerequisites with `./setup-system --offline-release`
while its package repositories are reachable, then install the complete archive
with `dotfiles-release`. Do not run `setup-tools` or `setup-asdf` for this route.

On a connected machine, run the reviewed entry points as the intended ordinary
user. Only `setup-system` uses `sudo`:

```bash
./setup-system
./setup-tools
# Optional online project runtimes, including .tool-versions support:
./setup-asdf terraform python nodejs terragrunt

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
`version|full_URL|SHA256` records for online tools and project runtimes, while
`validation.env` owns the validator list and records, including the only Task
pin. `TOOLS` and `OFFLINE_RELEASE_TOOLS` select the tools for each route,
including `fd`. Online setup installs kubectl and Helm directly by default.
The first record is the default. `ASDF_PLUGINS` is the sole asdf tool list and
pins plugin repositories and commits; asdf keeps responsibility for fetching and verifying
its plugins.
Asdf remains an optional online provider, independent of offline releases.
The tmux plugin `*_REPO` and `*_COMMIT` pairs also live in `versions.env`.

`system.env` owns OS package lists, installation checks and host setup
prerequisites. OS packages use the current repository candidates without
version pins. `probes.env` supplies version command arguments for both
installation, shell diagnostics and offline release health. Builder image pins live in
`release.env`.

`setup-system` defaults to the `setup` OS package profile; `--offline-release`
selects only the `runtime` profile. It never chooses a tool list. Each env
variable has a short purpose comment. Installer rerun guarantees and limits are
documented in [SETUP.md](SETUP.md#reruns-and-recovery).

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
`vim`. Git's editor and the shell's `EDITOR`/`VISUAL` defaults use system `vi`.
`old-nvim` is an unsupported
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
