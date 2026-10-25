# Dotfiles

Personal bash, tmux, neovim, oh my posh, etc., configuration for Linux x86-64.
Current CI targets are Debian 13, Ubuntu 24.04, Ubuntu 26.04 and Amazon Linux 2023.

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

The preferred deployment of this dotfiles is a built offline release attached to the GitHub release.
Download the standalone `dotfiles-release`, platform archive and their `.sha256` files
from the same GitHub release.

```bash
sha256sum --check --strict dotfiles-release.sha256
bash ./dotfiles-release setup
```

```bash
sha256sum --check --strict dotfiles-release.sha256 \
  dotfiles-COMMIT-PLATFORM.tar.gz.sha256
bash ./dotfiles-release verify ./dotfiles-COMMIT-PLATFORM.tar.gz
bash ./dotfiles-release install ./dotfiles-COMMIT-PLATFORM.tar.gz
bash ./dotfiles-release list
bash ./dotfiles-release health
bash ./dotfiles-release set dotfiles-COMMIT
bash ./dotfiles-release uninstall dotfiles-COMMIT
```

`verify` reads the platform from the archive and checks its structure and
checksums without installing or running its programs. `health [ID]` checks an
installed release and, for `current`, its public links. Install and set run the
same light runtime checks; `--skip-health` skips it.
`setup` detects the host OS and uses embedded runtime package lists to install.
`install` never runs setup, uses sudo or downloads tools. On a prepared host,
skip `setup` and install directly.

Alternatively on a machine with full internet access clone the repository and run below setup commands. Only `setup-system` uses `sudo`:

```bash
mkdir -p "$HOME/github.com/surbanski"
git clone git@github.com:surbanski-nr/dotfiles.git "$HOME/github.com/surbanski/dotfiles"
pushd "$HOME/github.com/surbanski/dotfiles"
```

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
operating system and tools see those files in proper directories like ~ or ~/.config,
but they stay in the git repository so that they get updated across machines after pulling.
The records package ownership under `$HOME/.local/state/bstow` (to know what to unlink when some package is deleted),
and protects existing regular files and foreign links.

Use `restow` after pulling deletions or renames. Preview `--force` before using it to adopt foreign links.

`tools.env` contains tool lists and their fixed versions `version|full_URL|SHA256`

`system.env` owns OS package lists, installation checks and host setup
prerequisites. OS packages use the current repository candidates without
version pins (distros are relatively stable and well tested and behind on versions, no need to overcomplicate this part).

## Testing

Bootstrap the pinned Task executable and run repository validation with:

```bash
bash scripts/install-validation-tool task
bin/task validate
```

Workflow validation runs locally without GitHub credentials. Set `GH_TOKEN`,
`GITHUB_TOKEN` or use an active `gh` login to additionally enable Zizmor's
online audits. The GitHub Actions workflow supplies its repository token.

Focused tasks include `validate:bash`, `validate:configs`, `validate:nvim2`,
`validate:scripts`, `validate:tmux`, `validate:tools` and `validate:workflows`.

`validate:bash` lints and tests Bash startup files and checks the syntax of
`bash` code blocks read directly from Markdown documentation with `bash -n`.

`validate:configs` checks YAML, JSON and Git configuration syntax and trailing
spaces and tabs in current text files, including tracked files and new files
that Git does not ignore.

`validate:tools` checks the tool definitions in `tools.env` and `validation.env`.

`validate:scripts` checks executable bits, lints shell scripts and tests
installers, offline releases and the validation scripts, including failure
handling and Ctrl+C cleanup.

Nvim2 lockfiles are checked by `validate:nvim2`.
