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

`setup` detects the host OS and uses embedded runtime package lists to install.
`verify` reads the platform from the archive and checks its structure without installing or running its programs.
`install` installs the package. It never runs setup, uses sudo or downloads tools. On a prepared host, skip `setup` and install only the tar.gz package.
`health [ID]` checks an installed release and, for `current`, its configuration links.

Alternatively on a machine with full internet access clone the repository and run below setup scripts. Only `setup-system` uses `sudo`:

```bash
mkdir -p "$HOME/github.com/surbanski"
git clone git@github.com:surbanski-nr/dotfiles.git "$HOME/github.com/surbanski/dotfiles"
pushd "$HOME/github.com/surbanski/dotfiles"
```

```bash
./setup-system
./setup-tools
./setup-asdf
./dotfiles-release set online

source "$HOME/.bashrc"
hash -r
dotfiles-check
```

Both flows expose tools through `~/dotfiles-releases/current/bin`.

If I can't modify the host, but docker is available another option is running
all those tools from a docker container. Compose in this repository runs it, with its own HOME
and a workspace bind mounts at `~/work`, shared host Neovim/tmux state, bin overrides and SSH agent,
and access to the host Docker socket (remove the mount if you don't want to run containers from that devcontainer).

```bash
docker compose up -d
docker compose exec dev bash
```

Inside Bash, use `tmux new-session -A -s work` to start or attach your session.

## Versions

`tools.env` contains tool lists and their fixed versions `version|full_URL|SHA256`

`system.env` contains OS package lists and host setup prerequisites for various platforms I test against. OS packages use the current repository version without pins (distros are relatively stable and well tested and behind on versions, I decided not to overcomplicate this part).

`platforms.env` contains platform aliases, Docker/LXD images and the OS lists
used for development, offline testing and release publication.

The devcontainer image pins its mise tools in the root `mise.toml`
and downloads in the generated `mise.lock`. Its Debian packages are
listed in `Dockerfile`. These image versions can change separately from host
installations. Mise and container image are the newest and experimental additions.

## Testing

Run `task` without arguments to list available tasks. `task dev` opens a
persistent Debian 13 LXD VM for development. Select another supported OS with
`task dev -- ubuntu2404`, `ubuntu2604` or `amazonlinux2023`.
`task test` builds, installs and tests offline packages for all four configured platforms,
and then builds and tests the development image. Use `task test -- debian13` to limit the
offline part to one platform. `task test:offline` and `task test:devcontainer`
run either part separately. Run them inside the VM to keep Docker images and
containers off the host.

Bootstrap the pinned Task executable and run repository validation with:

```bash
bash scripts/install-validation-tool task
./bin/task validate
```
