# Dotfiles

Personal bash, tmux, neovim, oh my posh, etc., configuration for Linux x86-64.
Current CI targets are Debian 13, Ubuntu 24.04, Ubuntu 26.04 and Amazon Linux 2023.

The intetion is to have a version controlled and easly reproducable development environment across the computers I use.

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
mkdir -p -m 700 "${XDG_RUNTIME_DIR:-$HOME/.ssh}"
export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-$HOME/.ssh}/dotfiles-ssh-agent.socket"
if [[ ! -S $SSH_AUTH_SOCK ]]; then
  eval "$(ssh-agent -a "$SSH_AUTH_SOCK" -s)"
fi
ssh-add "$HOME/.ssh/github"
ssh -o IdentitiesOnly=yes -i "$HOME/.ssh/github" -T git@github.com
```

#### Offline package

The preferred deployment of this dotfiles repo is a built offline release with tools attached to the GitHub release.
Download the standalone `dotfiles-release` script, platform archive and their `.sha256` files
from the same GitHub release. The archive does not contain os packages, only tools are packaged.

```bash
sha256sum --check --strict dotfiles-release.sha256 \
  dotfiles-COMMIT-PLATFORM.tar.gz.sha256

bash ./dotfiles-release setup
bash ./dotfiles-release verify ./dotfiles-COMMIT-PLATFORM.tar.gz
bash ./dotfiles-release install ./dotfiles-COMMIT-PLATFORM.tar.gz
bash ./dotfiles-release list
bash ./dotfiles-release health
bash ./dotfiles-release set dotfiles-COMMIT
bash ./dotfiles-release uninstall dotfiles-COMMIT
```

`setup` detects the host OS and uses embedded runtime package lists to install what it needs.
`verify` checks the archive content and its structure without installing or running its programs.
`install` installs the package with tools. It never runs setup, uses sudo or downloads from the Internet. On a prepared host, skip `setup` and install only the tar.gz package.
`health [ID]` checks an installed release and, for `current`, its configuration links.

#### Online package
Alternatively on a machine with full internet access clone the repository and run below setup scripts. Only `setup-system` uses `sudo`:

```bash
mkdir -p "$HOME/github.com/surbanski"
git clone git@github.com:surbanski-nr/dotfiles.git "$HOME/github.com/surbanski/dotfiles"
pushd "$HOME/github.com/surbanski/dotfiles"
```

Continue the installation from the checkout:

```bash
./setup-system
newgrp docker
./setup-tools
./setup-asdf
./dotfiles-release set online

source "$HOME/.bashrc"
hash -r
nvim --headless '+Nvim2ToolsInstallSync' '+qa!'
dotfiles-check
```

`newgrp` opens a new shell with the updated group membership. Alternatively, log
out and back in. The later `source "$HOME/.bashrc"` and `hash -r` refresh shell
configuration and command lookup.

`setup-tools` installs the Neovim executable and other CLI tools.
`Nvim2ToolsInstallSync` separately installs the configured Mason tools
(language servers, linters, formatters and debuggers) and Treesitter parsers.
Offline packages and container images install these dependencies during their
builds.

Both flows expose tools through `~/dotfiles-releases/current/bin`.

#### Devcontainer image

Another option is to run the development environment from inside a docker container.
Compose in this repository runs it, with its own HOME
and the host's `~/work` mounted at the same absolute path, shared host bin overrides and SSH agent,
and access to the host Docker socket (remove the mount if you don't want to run containers from that devcontainer).

Run these commands beside `compose.yaml` on the host to unlock a key and start the container with
your host UID/GID and access to both sockets:

```bash
mkdir -p -m 700 "${XDG_RUNTIME_DIR:-$HOME/.ssh}"
export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-$HOME/.ssh}/dotfiles-ssh-agent.socket"
if [[ ! -S $SSH_AUTH_SOCK ]]; then
  eval "$(ssh-agent -a "$SSH_AUTH_SOCK" -s)"
fi
ssh-add "$HOME/.ssh/github"

DOTFILES_UID="$(id -u)"
DOTFILES_GID="$(id -g)"
DOTFILES_DOCKER_GID="$(stat -c '%g' /var/run/docker.sock)"
export DOTFILES_UID DOTFILES_GID DOTFILES_DOCKER_GID

mkdir -p "$HOME/work" "$HOME/bin" \
  "${XDG_STATE_HOME:-$HOME/.local/state}/nvim2" \
  "${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect"

docker compose up -d --wait
docker compose exec --user devcontainer dev bash
```

## Versions

`tools.env` contains tool lists and their fixed versions `version|full_URL|SHA256`

`system.env` contains OS package lists and host setup prerequisites for various platforms I test against. OS packages use the current repository version without pins (distros are relatively stable, well tested and behind on versions, I decided not to overcomplicate this part).

`platforms.env` pins Docker and development VM images and contains the OS lists used for testing and release publication.

The devcontainer image is the latest and experimental addition, it installs its tools with mise via `mise.toml`
and downloads in the generated `mise.lock`, instead of using my own package manager.
Its Debian packages are listed in `Dockerfile`. These image versions can change separately from host
installations.

## Testing

Run `task` without arguments to list available tasks. `task dev` opens a
persistent Debian 13 LXD VM that I use for tool version upgrades or testing changes.
Select another supported OS with `task dev -- ubuntu2404`, `ubuntu2604` or `amazonlinux2023`.
`task test` builds, installs and tests offline packages for all four configured platforms,
and then builds and tests the development image. Use `task test -- debian13` to limit the
offline part to one platform. `task test:offline` and `task test:devcontainer`
run either part separately.

Bootstrap the pinned Task executable and run repository validation with:

```bash
bash scripts/install-validation-tool task
./bin/task validate
```

`task validate` runs linters and local fixture tests, including in GitHub Actions.
It works without Docker or LXD services.
