# Dotfiles

Personal Bash, tmux, Neovim, Oh My Posh, etc., configuration for Linux x86-64.
The targets are Debian 13, Ubuntu 24.04, Ubuntu 26.04 and Amazon Linux 2023.

The intetion is to have a version controlled and easly reproducable and version
controlled development environment across my computers.

### GitHub SSH access

Generate a key if you do not already have one:

```bash
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
ssh-keygen -t ed25519 \
  -C "122265380+surbanski-nr@users.noreply.github.com" \
  -f "$HOME/.ssh/github"
cat "$HOME/.ssh/github.pub"
```

```bash
if [[ -z ${SSH_AUTH_SOCK:-} ]]; then
  eval "$(ssh-agent -s)"
fi
ssh-add "$HOME/.ssh/github"
ssh -o IdentitiesOnly=yes -i "$HOME/.ssh/github" -T git@github.com
```

```bash
mkdir -p "$HOME/github.com/surbanski"
git clone git@github.com:surbanski-nr/dotfiles.git "$HOME/github.com/surbanski/dotfiles"
pushd "$HOME/github.com/surbanski/dotfiles"
```

### Deployment

The preferred deployment is a built offline release attached to a release.
No asdf installation or shims are needed for this route.
Prepare the target's system prerequisites with `./setup-system --offline-release`
while its package repositories are reachable, then install the complete archive
with `dotfiles-release` script. Do not run `setup-tools` or `setup-asdf` for this option.

Alternatively on a machine with full internet access run below commands. Only `setup-system` uses `sudo`:

```bash
./setup-system
./setup-tools
./setup-asdf

for file in "$HOME/.bash_profile" "$HOME/.bashrc"; do
  if [[ -f $file && ! -L $file && ! -e $file.before-dotfiles && ! -L $file.before-dotfiles ]]; then
    mv -- "$file" "$file.before-dotfiles"
  fi
done
./bstow -v -t "$HOME" stow \
  git tmux bash mc oh-my-posh k9s nvim2 gnupg

source "$HOME/.bashrc"
hash -r
dotfiles-check
```

`bstow` is an alternative to GNU Stow and manages package files as individual links,
records package ownership under `$HOME/.local/state/bstow`, and protects regular files and foreign links.
Use `restow` after pulling deletions or renames. Preview `--force` before using
it to adopt foreign links.

`tools.env` contains ordered `version|full_URL|SHA256` fixed records for tools and runtimes to be used,
while `validation.env` owns the validator list.

`tools-probes.env` supplies version command arguments for both installation,
shell diagnostics and offline release health. Builder image pins live in `release.env`.

`system.env` owns OS package lists, installation checks and host setup
prerequisites. OS packages use the current repository candidates without
version pins (the only place I trust with unfixed versions).

## Neovim

The active editor profile uses Neovim 0.12.5 or newer, built-in `vim.pack`, a
generated plugin lock and explicitly pinned external tools. Start it with:

```bash
NVIM_APPNAME=nvim2 nvim
```

or `v` alias.## Validation

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
