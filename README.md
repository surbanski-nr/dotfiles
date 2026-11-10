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
sha256sum --check --strict dotfiles-release.sha256 \
  dotfiles-COMMIT-PLATFORM.tar.gz.sha256
bash ./dotfiles-release verify ./dotfiles-COMMIT-PLATFORM.tar.gz
bash ./dotfiles-release setup
bash ./dotfiles-release install ./dotfiles-COMMIT-PLATFORM.tar.gz
bash ./dotfiles-release list
bash ./dotfiles-release health
bash ./dotfiles-release set dotfiles-COMMIT
bash ./dotfiles-release uninstall dotfiles-COMMIT
```

`verify` reads the platform from the archive and checks its structure without installing or running its programs.
`health [ID]` checks an installed release and, for `current`, its configuration links.
`setup` detects the host OS and uses embedded runtime package lists to install.
`install` never runs setup, uses sudo or downloads tools. On a prepared host,
skip `setup` and install only the tar.gz package.

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
./scripts/dotfiles-release set online

source "$HOME/.bashrc"
hash -r
dotfiles-check
```

Both flows expose tools through `~/dotfiles-releases/current/bin`.

Third alternative option and the initial approach for this dotfiles repository is to only clone it and then create symlinks to it from user home directory using `bstow`, my alternative to GNU Stow that manages package files as individual symlinks.
Operating system and tools see those files in proper directories like ~ or ~/.config,
but they stay in the git repository so that they get version controlled and updated across machines after pulling.
It records package ownership under `$HOME/.local/state/bstow` (to know what to unlink when some package is deleted),
and protects existing regular files and foreign links.

Use `restow` after pulling deletions or renames. Preview `--force` before using it to adopt foreign links.

## Versions

`tools.env` contains tool lists and their fixed versions `version|full_URL|SHA256`

`system.env` contains OS package lists and host setup prerequisites. OS packages use the current repository version without pins (distros are relatively stable and well tested and behind on versions, I decided not to overcomplicate this part).

`platforms.env` contains platform aliases, Docker/LXD images and the OS lists
used for development, offline testing and release publication. Generated
installation `release.env` files record selected tools and their versions.

## Testing

Run `task` without arguments to list available tasks. `task dev` opens a
persistent Debian 13 LXD VM for development. Select another supported OS with
`task dev -- ubuntu2404`, `ubuntu2604` or `amazonlinux2023`.
`task test` builds and qualifies offline packages in Docker; use
`task test -- debian13` to select one platform. Run it inside the VM to keep
Docker images and containers off the host.

Bootstrap the pinned Task executable and run repository validation with:

```bash
bash scripts/install-validation-tool task
./bin/task validate
```
