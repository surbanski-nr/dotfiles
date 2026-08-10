# Nvim2 platform releases

This document describes how to build, review, transfer, activate and roll back
a complete Nvim2 release. The release is the deployment unit for connected and
restricted machines.

The release contains:

- one exact Neovim version;
- one exact dotfiles Git commit and `nvim-pack-lock.json`;
- all plugin repositories at their locked commits;
- all pinned Mason language servers, formatters and linters;
- the configured Treesitter parsers, their revision metadata and queries;
- a platform and dependency manifest;
- checksums for every transferred artifact.

Do not update only one component directly on a restricted machine. Review an
update on a connected machine, build a new complete release, test it, and then
activate that release as a unit.

## Release matrix

Build a separate artifact for every target platform and architecture. Sharing
one Git commit and lockfile does not make compiled files portable.

Examples:

| Target | Builder image | Artifact identifier |
| --- | --- | --- |
| Ubuntu 24.04 x86-64 | `ubuntu:24.04` | `ubuntu-24.04-x86_64` |
| Ubuntu 26.04 x86-64 | `ubuntu:26.04` | `ubuntu-26.04-x86_64` |
| Amazon Linux 2 x86-64 | `amazonlinux:2` | `amzn-2-x86_64` |

The outer builder host can be Debian or Ubuntu because each artifact is built
inside its target image. Do not use an Ubuntu container for Amazon Linux 2.
Amazon Linux 2 uses an older glibc and different Python and Node versions.

The public Amazon Linux 2 image reports a support end date of 2026-06-30. Keep
this target only while the company provides an approved extended-support
package source. Plan its replacement with a supported platform.

Match these target properties:

- operating-system release;
- CPU architecture;
- username and absolute home path;
- Neovim version;
- Python major and minor version;
- Node major version.

Mason Python environments and some launchers contain absolute interpreter and
home paths. Treesitter parsers and some Mason tools are native binaries. A
bundle built under `/home/surbanski` should be activated under that same path.

## Record the target

Run this on the target before preparing its first release:

```bash
cat /etc/os-release
uname -m
getconf GNU_LIBC_VERSION
id -u
printf 'user=%s\nhome=%s\n' "$USER" "$HOME"
python3 --version
node --version
```

Save the output with the release request. The connected builder must use the
same values or compatible versions supplied by the same OS package sources.

## Create a connected builder on Debian or Ubuntu

A connected VM created from the same image as the target is preferred. When
one host builds the full matrix, run every target distribution in Podman. The
host distribution does not determine the artifact ABI.

Install Podman and prepare an output directory:

```bash
sudo apt-get update
sudo apt-get install -y podman
mkdir -p "$HOME/nvim2-builder-output"
```

Amazon Linux 2 builder:

```bash
podman pull public.ecr.aws/amazonlinux/amazonlinux:2
podman run --name nvim2-amzn2-builder -it \
  -v "$HOME/nvim2-builder-output:/out:Z" \
  public.ecr.aws/amazonlinux/amazonlinux:2 bash
```

Ubuntu 24.04 builder:

```bash
podman pull docker.io/library/ubuntu:24.04
podman run --name nvim2-ubuntu2404-builder -it \
  -v "$HOME/nvim2-builder-output:/out:Z" \
  docker.io/library/ubuntu:24.04 bash
```

Ubuntu 26.04 builder:

```bash
podman pull docker.io/library/ubuntu:26.04
podman run --name nvim2-ubuntu2604-builder -it \
  -v "$HOME/nvim2-builder-output:/out:Z" \
  docker.io/library/ubuntu:26.04 bash
```

Do not remove the builder until its release has passed the disconnected test.

### Install builder dependencies

Amazon Linux 2:

```bash
yum install -y \
  git curl tar gzip unzip xz \
  gcc gcc-c++ make \
  python3 python3-pip \
  findutils
```

The public Amazon Linux 2 repositories install Python 3.7 and do not provide
Node.js, npm or ripgrep. The current Nvim2 tools need Python 3.12 or newer,
Node.js 18 or newer, npm and ripgrep. Install approved RPMs for those commands
from the same company package source used by the restricted target, then run:

```bash
python3 -c 'import sys; assert sys.version_info >= (3, 12), sys.version'
node -e 'process.exit(Number(process.versions.node.split(".")[0]) < 18)'
command -v npm rg
```

Do not continue until this preflight passes. A public Amazon Linux 2 container
alone cannot build the current complete Nvim2 tool set.

Ubuntu 24.04 and 26.04:

```bash
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  git curl tar gzip unzip xz-utils \
  gcc g++ make \
  python3 python3-venv python3-pip \
  nodejs npm \
  ripgrep fd-find
```

Package names can differ in company repositories. The builder and target must
obtain Python and Node from equivalent package sources. If the current
`ansible-lint` dependency set changes its Python requirement, update the
preflight and rebuild all artifacts. Do not build the Python tools with
Homebrew when Homebrew is absent from the target.

Create a user whose name, UID and home match the target. Set these values from
the target inventory rather than copying the examples:

```bash
target_user=surbanski
target_uid=1000
target_home=/home/surbanski

groupadd --gid "$target_uid" "$target_user"
useradd --create-home --uid "$target_uid" --gid "$target_uid" \
  --home-dir "$target_home" --shell /bin/bash "$target_user"
su - "$target_user"
```

The remaining builder steps run as that user.

## Install Neovim in the builder

Use one reviewed Neovim release for all artifacts in the release set. The
official x86-64 Neovim 0.12.0 archive runs on Ubuntu 24.04 and 26.04:

```bash
version=v0.12.0
asset=nvim-linux-x86_64.tar.gz
install_dir="$HOME/.local/opt/nvim-$version"

mkdir -p "$HOME/bin" "$install_dir" "$HOME/release-inputs"
curl -fL \
  "https://github.com/neovim/neovim/releases/download/$version/$asset" \
  -o "$HOME/release-inputs/$asset"
tar -xzf "$HOME/release-inputs/$asset" \
  -C "$install_dir" \
  --strip-components=1
ln -sfn "$install_dir/bin/nvim" "$HOME/bin/nvim"
export PATH="$HOME/bin:$PATH"
nvim --version
```

Record and review the upstream archive checksum before using it in a release.

The official archive does not run on Amazon Linux 2 because it requires glibc
2.28 or newer and Amazon Linux 2 has glibc 2.26. Build the same Neovim commit
inside the Amazon Linux 2 builder:

```bash
yum install -y cmake3 ninja-build gettext libtool autoconf automake pkgconfig

version=v0.12.0
neovim_commit=fc7e5cf6c93fef08effc183087a2c8cc9bf0d75a
nvim_archive="nvim-$version-amzn-2-x86_64.tar.gz"
install_dir="$HOME/.local/opt/nvim-$version"
source_dir=$(mktemp -d)

git clone --quiet https://github.com/neovim/neovim.git "$source_dir/neovim"
git -C "$source_dir/neovim" checkout --detach "$neovim_commit"
test "$(git -C "$source_dir/neovim" rev-parse HEAD)" = "$neovim_commit"

make -C "$source_dir/neovim" \
  CMAKE=cmake3 \
  CMAKE_BUILD_TYPE=Release \
  CMAKE_INSTALL_PREFIX="$install_dir"
make -C "$source_dir/neovim" install \
  CMAKE=cmake3 \
  CMAKE_BUILD_TYPE=Release \
  CMAKE_INSTALL_PREFIX="$install_dir"

mkdir -p "$HOME/bin" "$HOME/release-inputs"
ln -sfn "$install_dir/bin/nvim" "$HOME/bin/nvim"
tar -C "$(dirname "$install_dir")" -czf \
  "$HOME/release-inputs/$nvim_archive" "$(basename "$install_dir")"
export PATH="$HOME/bin:$PATH"
nvim --version
```

The commit is the commit behind the reviewed `v0.12.0` tag. Change both values
together during a Neovim upgrade. Neovim's dependency build downloads source,
so this step runs only on the connected builder.

## Build a clean Nvim2 data directory

Every release starts from an empty Nvim2 data directory. Reusing a developer's
directory can include removed plugins, old parsers and unrelated Mason tools.

Clone the reviewed dotfiles commit and stow only Nvim2:

```bash
mkdir -p "$HOME/github.com/surbanski"
git clone https://github.com/surbanski-nr/dotfiles.git \
  "$HOME/github.com/surbanski/dotfiles"
cd "$HOME/github.com/surbanski/dotfiles"
git status --short
git rev-parse HEAD

./bstow --dry-run -t "$HOME" stow nvim2
./bstow -t "$HOME" stow nvim2
test ! -e "$HOME/.local/share/nvim2"
```

Install plugins, pinned Mason tools and configured Treesitter parsers:

```bash
timeout 1200s env NVIM_APPNAME=nvim2 \
  nvim --headless '+Nvim2ToolsInstallSync' '+qa!'
```

`Nvim2ToolsInstallSync` runs `MasonToolsInstallSync` and then installs or
updates the configured parsers. Mason startup installation and automatic
updates remain disabled.

Run the complete checks:

```bash
bash "$HOME/.config/nvim2/tests/check.sh"
```

`MasonToolsInstallSync` can report an individual download failure without
making Neovim exit nonzero. The checks are therefore mandatory. If a tool is
missing, inspect `~/.local/state/nvim2/mason.log`, correct the package or
network problem, rerun `Nvim2ToolsInstallSync`, and run the checks again. Never
package a release after only the install command succeeds.

Inspect the resulting sets before packaging:

```bash
find "$HOME/.local/share/nvim2/mason/packages" \
  -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort

find "$HOME/.local/share/nvim2/site/parser" \
  -maxdepth 1 -type f -name '*.so' -printf '%f\n' | sort

find -L "$HOME/.local/share/nvim2/mason/bin" -type l -print
```

The last command must print nothing. Compare the package and parser lists with
`lua/custom/lsp.lua` and `lua/custom/treesitter.lua`.

Test representative executables:

```bash
export PATH="$HOME/.local/share/nvim2/mason/bin:$PATH"
ruff --version
pyright --version
shellcheck --version
yamllint --version
lua-language-server --version
```

Open representative Python, Lua, Bash, Terraform, Ansible, Helm and YAML files
and confirm that LSP, formatting, linting, highlighting and folds work.

## Package the platform artifact

The runtime data archive must contain all five directories below:

- `site/pack/core`: locked plugin repositories;
- `site/parser`: compiled Treesitter parsers;
- `site/parser-info`: installed parser revisions;
- `site/queries`: Treesitter queries;
- `mason`: pinned tools, registries and launchers.

Treesitter query entries are normally absolute symlinks into the plugin
directory. Dereference only those query links while staging the release. Keep
Mason's internal symlinks unchanged.

```bash
cd "$HOME/github.com/surbanski/dotfiles"

commit=$(git rev-parse HEAD)
short_commit=$(git rev-parse --short=12 HEAD)
source /etc/os-release
platform_id="${ID}-${VERSION_ID}-$(uname -m)"
nvim_version=v0.12.0
case "$ID:$VERSION_ID" in
  ubuntu:24.04|ubuntu:26.04) nvim_archive=nvim-linux-x86_64.tar.gz ;;
  amzn:2) nvim_archive="nvim-$nvim_version-amzn-2-x86_64.tar.gz" ;;
  *)
    printf 'unsupported release target: %s:%s\n' "$ID" "$VERSION_ID" >&2
    exit 1
    ;;
esac
release_id="$(date -u +%Y%m%d)-${short_commit}-nvim-${nvim_version#v}"
out="/out/${release_id}/${platform_id}"
data_root="${XDG_DATA_HOME:-$HOME/.local/share}/nvim2"
stage=$(mktemp -d)

mkdir -p "$out" "$stage/nvim2/site/pack"
cp -a "$data_root/site/pack/core" "$stage/nvim2/site/pack/"
cp -a "$data_root/site/parser" "$stage/nvim2/site/"
cp -a "$data_root/site/parser-info" "$stage/nvim2/site/"
cp -aL "$data_root/site/queries" "$stage/nvim2/site/"
cp -a "$data_root/mason" "$stage/nvim2/"

tar -C "$stage/nvim2" -czf "$out/nvim2-data.tar.gz" .
git bundle create "$out/dotfiles.bundle" main
cp "$HOME/release-inputs/$nvim_archive" "$out/"
```

Write the activation values and builder details:

```bash
cat > "$out/release.env" <<EOF
RELEASE_ID=$release_id
PLATFORM_ID=$platform_id
DOTFILES_COMMIT=$commit
NVIM_VERSION=$nvim_version
NVIM_ARCHIVE=$nvim_archive
TARGET_HOME=$HOME
EOF

{
  cat /etc/os-release
  uname -a
  getconf GNU_LIBC_VERSION
  nvim --version
  python3 --version
  node --version
  git --version
  printf 'dotfiles_commit=%s\n' "$commit"
  sha256sum nvim2/.config/nvim2/nvim-pack-lock.json
} > "$out/build-manifest.txt"

if command -v rpm >/dev/null 2>&1; then
  rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE} %{ARCH}\n' | sort \
    > "$out/os-packages.txt"
else
  dpkg-query -W -f='${Package} ${Version} ${Architecture}\n' | sort \
    > "$out/os-packages.txt"
fi

cd "$out"
sha256sum \
  dotfiles.bundle \
  nvim2-data.tar.gz \
  "$nvim_archive" \
  release.env \
  build-manifest.txt \
  os-packages.txt \
  > SHA256SUMS
```

The artifact directory is the release for one platform. Build the remaining
platforms from the same dotfiles commit and Neovim version.

## Test without external network access

Before transfer, install the artifact into a clean VM or container matching
the target. Install only the approved OS packages, disable external network
access, and follow the target installation procedure below.

The disconnected test must pass:

```bash
bash "$HOME/.config/nvim2/tests/check.sh"
```

Also open representative project files. A successful test proves that the
archive contains every plugin, tool, parser and query needed at runtime.

## Install or upgrade a restricted machine

Do not extract a new archive over the active data directory. Store each release
under a versioned directory and make the canonical data path a symlink:

```text
~/.local/share/nvim2 -> ~/.local/share/nvim2-releases/RELEASE_ID
```

Mason's absolute paths continue to use `~/.local/share/nvim2`, so they resolve
through the active symlink. Stop all Nvim2 processes before activation.

### Verify and read the artifact

```bash
cd /path/to/platform-artifact
sha256sum -c SHA256SUMS
source ./release.env

[[ $HOME == "$TARGET_HOME" ]]
[[ $(uname -m) == "${PLATFORM_ID##*-}" ]]
```

Compare `/etc/os-release`, glibc, Python and Node with `build-manifest.txt`.
Use `os-packages.txt` to reproduce the relevant runtime packages from approved
repositories before continuing.

### Prepare versioned storage and rollback state

Convert an existing regular Nvim2 data directory into the first retained
release before recording rollback state:

```bash
mkdir -p "$HOME/.local/share/nvim2-releases" "$HOME/.local/state"

if [[ -d "$HOME/.local/share/nvim2" && ! -L "$HOME/.local/share/nvim2" ]]; then
  imported="$HOME/.local/share/nvim2-releases/imported-$(date -u +%Y%m%d-%H%M%S)"
  mv "$HOME/.local/share/nvim2" "$imported"
  ln -s "$imported" "$HOME/.local/share/nvim2"
fi
```

`~/bin/nvim` should likewise be a symlink to a complete versioned Neovim
installation. Preserve a manually installed Neovim directory before replacing
its launcher.

Record the active release before checking out the new dotfiles commit:

```bash
repo="$HOME/github.com/surbanski/dotfiles"
rollback_file="$HOME/.local/state/nvim2-release-rollback.env"

previous_commit=$(git -C "$repo" rev-parse HEAD 2>/dev/null || true)
previous_data=$(readlink -f "$HOME/.local/share/nvim2" 2>/dev/null || true)
previous_nvim=$(readlink -f "$HOME/bin/nvim" 2>/dev/null || true)

printf 'PREVIOUS_COMMIT=%q\nPREVIOUS_DATA=%q\nPREVIOUS_NVIM=%q\n' \
  "$previous_commit" "$previous_data" "$previous_nvim" \
  > "$rollback_file"
```

### Install the versioned Neovim runtime

```bash
nvim_dir="$HOME/.local/opt/nvim-$NVIM_VERSION"
mkdir -p "$HOME/bin" "$nvim_dir"
tar -xzf "$NVIM_ARCHIVE" -C "$nvim_dir" --strip-components=1
"$nvim_dir/bin/nvim" --version
```

### Install the matching dotfiles commit

For a new checkout:

```bash
mkdir -p "$HOME/github.com/surbanski"
git clone dotfiles.bundle "$HOME/github.com/surbanski/dotfiles"
cd "$HOME/github.com/surbanski/dotfiles"
git checkout --detach "$DOTFILES_COMMIT"
```

For an existing checkout:

```bash
cd "$HOME/github.com/surbanski/dotfiles"
git status --short
git fetch /path/to/platform-artifact/dotfiles.bundle \
  main:refs/remotes/offline/main
git checkout --detach "$DOTFILES_COMMIT"
```

Do not discard local changes. Resolve or preserve them before switching the
configuration commit.

Stow the profile without starting Neovim:

```bash
./bstow --dry-run -t "$HOME" stow nvim2
./bstow -t "$HOME" stow nvim2
```

### Extract the new data release

```bash
release_dir="$HOME/.local/share/nvim2-releases/$RELEASE_ID"
mkdir -p "$release_dir"
tar -C "$release_dir" -xzf /path/to/platform-artifact/nvim2-data.tar.gz
```

### Activate the release

Switch both symlinks:

```bash
data_link="$HOME/.local/share/nvim2"
data_next="$HOME/.local/share/.nvim2-next.$$"
nvim_next="$HOME/bin/.nvim-next.$$"

ln -s "$release_dir" "$data_next"
mv -Tf "$data_next" "$data_link"

ln -s "$nvim_dir/bin/nvim" "$nvim_next"
mv -Tf "$nvim_next" "$HOME/bin/nvim"
```

Validate immediately:

```bash
export PATH="$HOME/bin:$PATH"
bash "$HOME/.config/nvim2/tests/check.sh"
NVIM_APPNAME=nvim2 nvim
```

Do not run `Nvim2ToolsInstallSync`, `MasonUpdate`, `TSUpdate` or
`vim.pack.update()` on the restricted machine. Those are builder operations.

## Roll back

Stop Nvim2, restore the previous dotfiles commit and repoint both symlinks:

```bash
rollback_file="$HOME/.local/state/nvim2-release-rollback.env"
source "$rollback_file"

cd "$HOME/github.com/surbanski/dotfiles"
if [[ -n $PREVIOUS_COMMIT ]]; then
  git checkout --detach "$PREVIOUS_COMMIT"
fi

data_next="$HOME/.local/share/.nvim2-rollback.$$"
nvim_next="$HOME/bin/.nvim-rollback.$$"

if [[ -n $PREVIOUS_DATA ]]; then
  ln -s "$PREVIOUS_DATA" "$data_next"
  mv -Tf "$data_next" "$HOME/.local/share/nvim2"
fi

if [[ -n $PREVIOUS_NVIM ]]; then
  ln -s "$PREVIOUS_NVIM" "$nvim_next"
  mv -Tf "$nvim_next" "$HOME/bin/nvim"
fi

bash "$HOME/.config/nvim2/tests/check.sh"
```

Keep at least the current and previous release directories. Delete an old
release only after the replacement has been used successfully.

## Prepare upgrades on a trusted machine

An upgrade can change any of these layers:

| Layer | Version source |
| --- | --- |
| Neovim | release artifact and `NVIM_VERSION` |
| Plugins, including Mason plugins | `nvim-pack-lock.json` |
| Language servers | exact entries in `lua/custom/lsp.lua` |
| Formatters and linters | exact entries in `lua/custom/lsp.lua` |
| Treesitter CLI | exact entry in `lua/custom/lsp.lua` |
| Treesitter parser revisions | locked `nvim-treesitter` plugin commit |
| Enabled parser set | `lua/custom/treesitter.lua` |

Treat the resulting combination as a new platform release even when only one
entry changed.

### Baseline

```bash
cd "$HOME/github.com/surbanski/dotfiles"
git status --short
git switch -c "nvim2-upgrade-$(date -u +%Y%m%d)"
bash "$HOME/.config/nvim2/tests/check.sh"
```

Do not mix unrelated dotfile changes into the release review.

### Update plugins

Start an interactive Nvim2 session on the connected builder:

```bash
NVIM_APPNAME=nvim2 nvim
```

After Nvim2 opens, type one of these commands and press Enter:

```vim
:lua vim.pack.update()
:lua vim.pack.update({ 'gitsigns.nvim' })
:lua vim.pack.update({ 'PLUGIN_1', 'PLUGIN_2' })
```

The first command checks every managed plugin. The second checks one plugin,
and the third checks a related group. `vim.pack.update()` downloads the remote
changes and then opens the built-in confirmation buffer. There is no separate
`:PackUpdate` command or update-window launcher. Do not pass
`{ force = true }`, because that applies changes without the review window.

In the update window:

1. review every old and proposed commit;
2. use `[[` and `]]` to move between plugins;
3. use `K` for details;
4. skip an unapproved plugin with `gra`;
5. use `:write` to apply or `:quit` to cancel;
6. use `:restart` after applying.

Review the resulting lockfile and plugin diff in another terminal. Run the
complete checks before committing `nvim-pack-lock.json`.

Mason itself consists of normal plugins. Update `mason.nvim`,
`mason-lspconfig.nvim` and `mason-tool-installer.nvim` through this plugin
workflow.

### Update language servers, formatters and linters

These are Mason tools rather than plugins. Their exact versions are in
`lua/custom/lsp.lua`.

1. Run `:MasonUpdate` to refresh registry metadata.
2. Inspect the upstream release, checksums and release notes.
3. Change one exact version in `lua/custom/lsp.lua`.
4. Restart Neovim.
5. Run `:Nvim2ToolsInstallSync`.
6. Verify the executable's version.
7. Exercise the corresponding LSP, formatter or linter.
8. Run `tests/check.sh`.
9. Commit the exact version change.

Do not use `MasonToolsUpdateSync` as a version-selection mechanism. It does
not change the reviewed pins.

### Update Treesitter

Parser revisions are defined by the locked `nvim-treesitter` plugin commit.
After updating that plugin, run:

```vim
:Nvim2ToolsInstallSync
```

Review changes in the plugin's `lua/nvim-treesitter/parsers.lua`, then test all
supported languages. Adding or removing a language changes the list in
`lua/custom/treesitter.lua`. Removing an entry does not remove an already
installed parser, so the final platform artifact must be built from an empty
data directory.

### Update Neovim

A Neovim update requires a fresh platform build. Parser ABI, APIs and plugin
compatibility can change even when the configuration does not.

1. review and select the exact Neovim release;
2. install it in each clean platform builder;
3. restore locked plugins;
4. install all pinned tools and rebuild every parser;
5. run health and smoke checks;
6. build all three platform artifacts from the same dotfiles commit;
7. test all three artifacts without external network access;
8. keep the prior release for rollback.

## Hardening during upgrades

`lua/custom/hardening.lua` removes Kickstart's `PackChanged` build hook. It
does not block `vim.pack.update()`. It prevents plugin-controlled build steps
and the automatic `TSUpdate` action.

That is safe for the current plugin set:

- `telescope-fzf-native.nvim` is not installed;
- LuaSnip's optional `jsregexp` build is not used;
- parser installation is explicit through `Nvim2ToolsInstallSync`.

A future plugin that requires compilation or post-update generation will not
be ready automatically. Add an explicit reviewed build step to this release
process and test it in every platform image. Do not weaken hardening merely to
make a plugin install itself silently.

The current hardening clears all `PackChanged` handlers present at that point.
It should eventually be narrowed to the known Kickstart build handler so a
future approved handler is not removed accidentally.

## Validation scope

`tests/check.sh` is suitable for release validation and is inexpensive enough
to run after every accepted update. It checks locked plugins, pinned Mason
versions, configured parser presence, mappings, commands and several daily
workflows.

Current limitations are:

- extra Mason packages and parsers are not rejected;
- parser revisions and query completeness are not verified;
- most Mason executables are not started;
- only a subset of LSP, formatter and linter behavior is exercised;
- a plugin can have local modifications while retaining its locked Git commit.

Clean builders prevent most stale-extra problems. Continue inspecting package
and parser inventories until those checks are automated.
