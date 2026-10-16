# Dotfiles

Personal bash, tmux, neovim, oh my posh, etc., configuration for Linux x86-64.
Current targets are Debian 13, Ubuntu 24.04, Ubuntu 26.04 and Amazon Linux 2023.

The intetion is to have a version controlled and easly reproducable development environment across my computers.

### New machine setup

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

The preferred deployment of this dotfiles is a built offline release attached to GitHub release.
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
./bstow -v -t "$HOME" stow git ssh tmux bash mc oh-my-posh k9s nvim2 gnupg

source "$HOME/.bashrc"
hash -r
dotfiles-check
```

`bstow` is my alternative to GNU Stow that manages package files as individual symlinks,
records package ownership under `$HOME/.local/state/bstow`, and protects existing regular files and foreign links.
Use `restow` after pulling deletions or renames. Preview `--force` before using it to adopt foreign links.

`tools.env` contains tool lists and their fixed versions `version|full_URL|SHA256`

`system.env` owns OS package lists, installation checks and host setup
prerequisites. OS packages use the current repository candidates without
version pins (the only place I trust with unfixed versions as distros are relatively stable and well tested).

## Testing

Bootstrap the pinned Task executable and run repository validation with:

```bash
bash scripts/install-validation-tool task
.cache/validation-tools/bin/task validate
```

Workflow validation runs locally without GitHub credentials. Set `GH_TOKEN`,
`GITHUB_TOKEN` or use an active `gh` login to additionally enable Zizmor's
online audits. The GitHub Actions workflow supplies its repository token.

Focused tasks include `validate:bash`, `validate:configs`, `validate:nvim2`,
`validate:repo`, `validate:scripts` and `validate:workflows`.
