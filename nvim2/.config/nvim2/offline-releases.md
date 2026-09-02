# Nvim2 offline releases

This document describes how to build, review, transfer, activate and roll back
a complete Nvim2 release. The release is the deployment unit for connected and
restricted machines.

The release contains:

- one exact Neovim version;
- one exact Node.js runtime and ripgrep version;
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

| Target | Builder image | User and home | Artifact identifier |
| --- | --- | --- | --- |
| Ubuntu 24.04 x86-64 | `ubuntu:24.04` | `surbanski`, `/home/surbanski` | `ubuntu-24.04-x86_64` |
| Ubuntu 26.04 x86-64 | `ubuntu:26.04` | `surbanski`, `/home/surbanski` | `ubuntu-26.04-x86_64` |
| Amazon Linux 2023 x86-64 | `amazonlinux:2023` | `ec2-user`, `/home/ec2-user` | `amzn-2023-x86_64` |

The outer builder host can be Debian or Ubuntu because each artifact is built
inside its target image. Do not use an Ubuntu container for Amazon Linux 2023.
Its glibc, Python packages and native tool compatibility differ from Ubuntu.
Amazon Linux 2 is not a release target because its public support ended on
2026-06-30.

Match these target properties:

- operating-system release;
- CPU architecture;
- username and absolute home path;
- Neovim version;
- Python major and minor version;
- reviewed Node.js release included in the artifact.

Mason Python environments and some launchers contain absolute interpreter and
home paths. Treesitter parsers and some Mason tools are native binaries. An
Ubuntu bundle built under `/home/surbanski` must use that path on the target;
the Amazon Linux bundle similarly requires `/home/ec2-user`.

## Build a release with GitHub Actions

The `Build Nvim2 offline release` workflow builds and tests all missing
platform archives, then uploads them directly to an existing GitHub release.
It does not use workflow artifacts, create releases or publish drafts.

Release tags have this exact format:

```text
nvim2-<full 40-character lowercase commit SHA>
```

The suffix must match the commit referenced by the tag. The workflow checks
out that commit explicitly, so later unrelated changes on `main` do not enter
the release.

Create a draft release and tag from the reviewed commit:

```bash
commit=$(git rev-parse HEAD)
tag="nvim2-$commit"
gh release create "$tag" \
  --target "$commit" \
  --draft \
  --title "$commit" \
  --notes "Offline Nvim2 release for $commit"
```

Creating the tag triggers `.github/workflows/nvim2-release.yml`. Its preflight
waits briefly for the release to become readable. If the release does not
exist, the run succeeds without starting a builder. Use the manual workflow
when a tag run misses the draft or a build must be retried:

```bash
gh workflow run nvim2-release.yml \
  --ref main \
  -f release_tag="$tag" \
  -f force=false
```

Normal runs compare these expected assets with the existing release and build
only missing platforms:

```text
nvim2-offline-ubuntu-24.04-x86_64.tar.gz
nvim2-offline-ubuntu-26.04-x86_64.tar.gz
nvim2-offline-amzn-2023-x86_64.tar.gz
```

Download and unpack the archive for the target before following the install
steps in this runbook:

```bash
platform=ubuntu-24.04-x86_64
mkdir -p "$HOME/nvim2-release/$platform"
gh release download "$tag" \
  --pattern "nvim2-offline-$platform.tar.gz" \
  --dir "$HOME/nvim2-release"
tar -xzf "$HOME/nvim2-release/nvim2-offline-$platform.tar.gz" \
  -C "$HOME/nvim2-release/$platform"
```

GitHub records a SHA-256 digest for every uploaded release asset. Record and
compare that digest before transferring the archive. After extraction, the
existing `SHA256SUMS` verifies every file used by the target installation.

If an existing asset may be bad, run the workflow manually with `force=true`.
That rebuilds, tests and replaces all three assets. Automatic tag runs never
replace an existing asset. Keep the release as a draft until all assets have
passed review. Published immutable releases cannot be repaired in place.

```bash
gh workflow run nvim2-release.yml \
  --ref main \
  -f release_tag="$tag" \
  -f force=true
```

Every matrix job uses a pinned target container image, runs `tests/check.sh`,
installs its artifact into a clean runtime container with `--network none`,
and runs the checks again. Each release asset contains the platform files and
their internal `SHA256SUMS`. Builds use the exact versions in
`nvim2-release.env`.

The workflow uses standard GitHub-hosted Linux runners. It uploads directly to
the release, so large packages do not consume retained GitHub Actions artifact
storage or expire with workflow-run retention. A release asset remains until
the asset, release or repository is deleted. GitHub limits each release asset
to less than 2 GiB; the workflow checks that limit before upload.

## Record the target

Run this on the target before preparing its first release:

```bash
cat /etc/os-release
uname -m
getconf GNU_LIBC_VERSION
id -u
printf 'user=%s\nhome=%s\n' "$USER" "$HOME"
python3.12 --version 2>/dev/null || python3 --version
node --version 2>/dev/null || true
```

Save the output with the release request. The connected builder must use the
same values or compatible versions supplied by the same OS package sources.
Node.js does not need to exist before deployment because its reviewed archive
is part of the release.

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

Amazon Linux 2023 builder:

```bash
podman pull public.ecr.aws/amazonlinux/amazonlinux:2023
podman run --name nvim2-amzn2023-builder -it \
  -v "$HOME/nvim2-builder-output:/out:Z" \
  public.ecr.aws/amazonlinux/amazonlinux:2023 bash
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

Amazon Linux 2023:

```bash
dnf install -y \
  git wget ca-certificates openssh-clients \
  tar gzip unzip xz \
  gcc gcc-c++ make \
  python3.12 python3.12-pip \
  cargo clang-devel \
  tmux findutils which patch
```

The image already supplies `curl`, coreutils and GnuPG through minimal
packages. Do not request their full variants because DNF reports a conflict.
The default `python3` remains Python 3.9 after Python 3.12 is
installed, so expose the required interpreter through the target home:

```bash
mkdir -p "$HOME/bin"
ln -sfn /usr/bin/python3.12 "$HOME/bin/python3"
ln -sfn /usr/bin/python3.12 "$HOME/bin/python"
export PATH="$HOME/bin:$PATH"
python3 -c 'import sys; assert sys.version_info >= (3, 12), sys.version'
```

The repository's Node.js 18 package is too old for the pinned TypeScript
Language Server, which requires Node.js 20 or newer. The repository also lacks
ripgrep. Install both from the reviewed archives in the next section.

Ubuntu 24.04 and 26.04:

```bash
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  git curl wget ca-certificates tar gzip unzip xz-utils \
  gcc g++ make \
  python3 python3-venv python3-pip \
  ripgrep fd-find
```

Package names can differ in company repositories. The builder and target must
obtain Python from equivalent package sources. If the current `ansible-lint`
dependency set changes its Python requirement, update the preflight and rebuild
all artifacts. Do not build the Python tools with Homebrew when Homebrew is
absent from the target. Node.js comes from the reviewed archive below.

Create a user whose name, UID and home match the target. Set these values from
the target inventory rather than copying the examples. The Ubuntu 26.04 image
already owns UID 1000 with an `ubuntu` user, so reuse and rename an existing UID
owner instead of assuming the UID is free:

```bash
target_user=surbanski # Use ec2-user on Amazon Linux 2023.
target_uid=1000
target_home="/home/$target_user"

existing_user=$(getent passwd "$target_uid" | cut -d: -f1)
if [[ -n $existing_user && $existing_user != "$target_user" ]]; then
  existing_group=$(id -gn "$existing_user")
  usermod --login "$target_user" --home "$target_home" --move-home \
    --shell /bin/bash "$existing_user"
  if [[ $existing_group != "$target_user" ]]; then
    groupmod --new-name "$target_user" "$existing_group"
  fi
elif ! id "$target_user" >/dev/null 2>&1; then
  groupadd --gid "$target_uid" "$target_user"
  useradd --create-home --uid "$target_uid" --gid "$target_uid" \
    --home-dir "$target_home" --shell /bin/bash "$target_user"
fi
su - "$target_user"
```

The remaining builder steps run as that user.

## Install Node.js and ripgrep in the builder

Use one reviewed Node.js release for every artifact in the release set. The
official archive runs on Ubuntu 24.04, Ubuntu 26.04 and Amazon Linux 2023.
Select an exact Node.js 22 release and verify it against the checksum published
with that release:

```bash
node_version=${NODE_VERSION:?Set NODE_VERSION to a reviewed Node.js 22 release without v}
node_asset="node-v${node_version}-linux-x64.tar.xz"
node_base="https://nodejs.org/download/release/v${node_version}"
node_dir="$HOME/.local/opt/node-v${node_version}"

mkdir -p "$HOME/bin" "$node_dir" "$HOME/release-inputs"
curl -fL "$node_base/SHASUMS256.txt" \
  -o "$HOME/release-inputs/node-v${node_version}-SHASUMS256.txt"
node_checksum=$(
  awk -v asset="$node_asset" '$2 == asset { print $1 }' \
    "$HOME/release-inputs/node-v${node_version}-SHASUMS256.txt"
)
test -n "$node_checksum"
curl -fL "$node_base/$node_asset" \
  -o "$HOME/release-inputs/$node_asset"
printf '%s  %s\n' "$node_checksum" "$HOME/release-inputs/$node_asset" |
  sha256sum --check --strict
tar -xJf "$HOME/release-inputs/$node_asset" \
  -C "$node_dir" --strip-components=1
for command in node npm npx corepack; do
  ln -sfn "$node_dir/bin/$command" "$HOME/bin/$command"
done
export PATH="$HOME/bin:$PATH"
node --version
npm --version
```

Mason's npm installs can pause after downloads with older npm releases. Use a
reviewed current npm only on the connected builder. The offline target receives
the unchanged official Node archive and does not run npm or Mason installation:

```bash
npm view npm version
npm_version=${NPM_VERSION:?Set NPM_VERSION to the reviewed exact release}
env NPM_CONFIG_AUDIT=false npm install --global "npm@$npm_version"
npm --version
```

Amazon Linux 2023 does not package ripgrep. Resolve a reviewed release, verify
the GitHub release-asset digest and keep its archive for the offline target:

```bash
rg_tag=${RG_VERSION:-$(
  curl -fsSL https://api.github.com/repos/BurntSushi/ripgrep/releases/latest |
    python3 -c 'import json, sys; print(json.load(sys.stdin)["tag_name"])'
)}
rg_version=${rg_tag#v}
rg_asset="ripgrep-${rg_version}-x86_64-unknown-linux-musl.tar.gz"
rg_digest=$(
  curl -fsSL \
    "https://api.github.com/repos/BurntSushi/ripgrep/releases/tags/$rg_tag" |
    ASSET="$rg_asset" python3 -c '
import json, os, sys
assets = json.load(sys.stdin)["assets"]
print(next(item["digest"] for item in assets if item["name"] == os.environ["ASSET"]))
'
)
case "$rg_digest" in
  sha256:*) rg_checksum=${rg_digest#sha256:} ;;
  *) printf 'Release metadata has no SHA-256 digest for %s\n' "$rg_asset" >&2; exit 1 ;;
esac

rg_stage=$(mktemp -d)
curl -fL \
  "https://github.com/BurntSushi/ripgrep/releases/download/$rg_tag/$rg_asset" \
  -o "$HOME/release-inputs/$rg_asset"
printf '%s  %s\n' "$rg_checksum" "$HOME/release-inputs/$rg_asset" |
  sha256sum --check --strict
tar -xzf "$HOME/release-inputs/$rg_asset" -C "$rg_stage"
install -m 0755 \
  "$rg_stage/ripgrep-${rg_version}-x86_64-unknown-linux-musl/rg" \
  "$HOME/bin/rg"
rg --version
```

## Install Neovim in the builder

Use one reviewed Neovim release for all artifacts in the release set. Resolve
the latest stable tag once, or set `NVIM_VERSION=vX.Y.Z` first to reproduce a
specific reviewed release. Keep the exported value for every builder in the
release matrix:

```bash
version=${NVIM_VERSION:-$(
  curl -fsSL https://api.github.com/repos/neovim/neovim/releases/latest |
    python3 -c 'import json, sys; print(json.load(sys.stdin)["tag_name"])'
)}
export NVIM_VERSION=$version
printf 'Selected Neovim release: %s\n' "$NVIM_VERSION"
```

The official x86-64 archive runs on Ubuntu 24.04, Ubuntu 26.04 and Amazon Linux
2023. Derive its published digest from the selected release metadata:

```bash
version=${NVIM_VERSION:?Set NVIM_VERSION to the reviewed Neovim tag}
asset=nvim-linux-x86_64.tar.gz
digest=$(
  curl -fsSL "https://api.github.com/repos/neovim/neovim/releases/tags/$version" |
    ASSET="$asset" python3 -c '
import json, os, sys
assets = json.load(sys.stdin)["assets"]
print(next(item["digest"] for item in assets if item["name"] == os.environ["ASSET"]))
'
)
case "$digest" in
  sha256:*) checksum=${digest#sha256:} ;;
  *) printf 'Release metadata has no SHA-256 digest for %s\n' "$asset" >&2; exit 1 ;;
esac
install_dir="$HOME/.local/opt/nvim-$version"

printf 'Version: %s\nAsset:   %s\nSHA-256: %s\n' "$version" "$asset" "$checksum"
mkdir -p "$HOME/bin" "$install_dir" "$HOME/release-inputs"
curl -fL \
  "https://github.com/neovim/neovim/releases/download/$version/$asset" \
  -o "$HOME/release-inputs/$asset"
printf '%s  %s\n' "$checksum" "$HOME/release-inputs/$asset" | \
  sha256sum --check --strict
tar -xzf "$HOME/release-inputs/$asset" \
  -C "$install_dir" \
  --strip-components=1
ln -sfn "$install_dir/bin/nvim" "$HOME/bin/nvim"
export PATH="$HOME/bin:$PATH"
nvim --version
```

Review the resolved tag, asset and digest against the release page before
packaging. The digest is read from GitHub's release asset metadata and is not
duplicated in this runbook.

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

On Ubuntu, install plugins, pinned Mason tools and configured Treesitter
parsers in one operation:

```bash
timeout 1200s env NVIM_APPNAME=nvim2 \
  nvim --headless '+Nvim2ToolsInstallSync' '+qa!'
```

On Amazon Linux 2023, Mason's upstream Tree-sitter CLI binary currently needs
glibc 2.39, while the platform provides glibc 2.34. Install the Mason tools
first, compile the same pinned CLI version from its official Rust crate, and
then build the parsers:

```bash
timeout 1200s env NPM_CONFIG_AUDIT=false NVIM_APPNAME=nvim2 \
  nvim --headless '+MasonToolsInstallSync' '+qa!'

tree_sitter_version=$(
  NVIM_APPNAME=nvim2 nvim --headless \
    "+lua for _, tool in ipairs(require('custom.lsp').tools) do if tool[1] == 'tree-sitter-cli' then io.write(tool.version:gsub('^v', '')) end end" \
    '+qa!'
)
test -n "$tree_sitter_version"
tree_sitter_root="$HOME/.local/opt/tree-sitter-cli-$tree_sitter_version"
tree_sitter_binary=$(
  readlink -f "$HOME/.local/share/nvim2/mason/bin/tree-sitter"
)

timeout 1200s cargo install tree-sitter-cli \
  --version "$tree_sitter_version" \
  --locked \
  --root "$tree_sitter_root"
install -m 0755 \
  "$tree_sitter_root/bin/tree-sitter" \
  "$tree_sitter_binary"
"$HOME/.local/share/nvim2/mason/bin/tree-sitter" --version

timeout 1200s env NVIM_APPNAME=nvim2 \
  nvim --headless '+Nvim2ToolsInstallSync' '+qa!'
```

This direct `MasonToolsInstallSync` call is an AL2023 builder step, not an
alternative update workflow. The final `Nvim2ToolsInstallSync` still verifies
the pinned Mason inventory and installs every configured parser. Cargo and
Clang are builder-only packages and are not required on the offline target.

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

Open representative Python, Lua, Bash, TypeScript, TSX, Terraform, Ansible,
Helm and YAML files and confirm that the configured LSP, formatting, linting,
highlighting and folds work.

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
nvim_version=$(nvim --version | awk 'NR == 1 { print $2; exit }')
node_version=$(node --version | sed 's/^v//')
rg_version=$(rg --version | awk 'NR == 1 { print $2; exit }')
case "$ID:$VERSION_ID" in
  ubuntu:24.04|ubuntu:26.04|amzn:2023) ;;
  *)
    printf 'unsupported release target: %s:%s\n' "$ID" "$VERSION_ID" >&2
    exit 1
    ;;
esac
nvim_archive=nvim-linux-x86_64.tar.gz
node_archive="node-v${node_version}-linux-x64.tar.xz"
rg_archive="ripgrep-${rg_version}-x86_64-unknown-linux-musl.tar.gz"
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
git bundle create "$out/dotfiles.bundle" HEAD main
cp "$HOME/release-inputs/$nvim_archive" "$out/"
cp "$HOME/release-inputs/$node_archive" "$out/"
cp "$HOME/release-inputs/$rg_archive" "$out/"
```

Write the activation values and builder details:

```bash
cat > "$out/release.env" <<EOF
RELEASE_ID=$release_id
PLATFORM_ID=$platform_id
DOTFILES_COMMIT=$commit
NVIM_VERSION=$nvim_version
NVIM_ARCHIVE=$nvim_archive
NODE_VERSION=$node_version
NODE_ARCHIVE=$node_archive
RG_VERSION=$rg_version
RG_ARCHIVE=$rg_archive
TARGET_HOME=$HOME
EOF

{
  cat /etc/os-release
  uname -a
  getconf GNU_LIBC_VERSION
  nvim --version
  node --version
  npm --version
  python3 --version
  rg --version | head -n 1
  tmux -V
  "$data_root/mason/bin/tree-sitter" --version
  printf 'tree_sitter_cli_sha256='
  sha256sum \
    "$data_root/mason/packages/tree-sitter-cli/tree-sitter-linux-x64" |
    awk '{ print $1 }'
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
  "$node_archive" \
  "$rg_archive" \
  release.env \
  build-manifest.txt \
  os-packages.txt \
  > SHA256SUMS
```

The artifact directory is the release for one platform. Build the remaining
platforms from the same dotfiles commit and Neovim, Node.js and ripgrep
versions.

## Test without external network access

Before transfer, install the artifact into a clean VM or container matching
the target. Install only the approved OS packages, disable external network
access, and follow the target installation procedure below.

For Podman, prepare a clean runtime container while connected, install only
the target OS packages, and commit that base. Launch the actual release test
with no network instead of relying on a live network disconnect:

```bash
podman commit nvim2-amzn2023-runtime \
  localhost/nvim2-amzn2023-runtime:validation
podman run --name nvim2-amzn2023-airgap --network none -it \
  -v /path/to/platform-artifact:/artifact:ro,Z \
  localhost/nvim2-amzn2023-runtime:validation bash

curl --max-time 3 -fsS https://github.com
# Expected: name resolution or connection failure.
```

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

### Install target operating-system packages

Install packages from the approved operating-system repository before
disconnecting the machine. Amazon Linux 2023 needs:

```bash
sudo dnf install -y \
  git ca-certificates \
  tar gzip xz \
  python3.12 tmux findutils which
```

Neovim, Node.js and ripgrep come from the checked release artifact. Compilers,
Cargo, Clang and npm installation are builder-only concerns.

### Verify and read the artifact

```bash
cd /path/to/platform-artifact
sha256sum -c SHA256SUMS
source ./release.env

[[ $HOME == "$TARGET_HOME" ]]
[[ $(uname -m) == "${PLATFORM_ID##*-}" ]]
```

Compare `/etc/os-release`, glibc and Python 3.12 with `build-manifest.txt`. Use
`os-packages.txt` to reproduce the relevant runtime packages from approved
repositories before continuing. Node.js is checked after extracting its
release archive.

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
previous_node=$(readlink -f "$HOME/bin/node" 2>/dev/null || true)
previous_rg=$(readlink -f "$HOME/bin/rg" 2>/dev/null || true)

printf 'PREVIOUS_COMMIT=%q\nPREVIOUS_DATA=%q\nPREVIOUS_NVIM=%q\nPREVIOUS_NODE=%q\nPREVIOUS_RG=%q\n' \
  "$previous_commit" "$previous_data" "$previous_nvim" \
  "$previous_node" "$previous_rg" \
  > "$rollback_file"
```

### Install the versioned runtimes

```bash
nvim_dir="$HOME/.local/opt/nvim-$NVIM_VERSION"
node_dir="$HOME/.local/opt/node-v$NODE_VERSION"
rg_dir="$HOME/.local/opt/ripgrep-$RG_VERSION"
mkdir -p "$HOME/bin" "$nvim_dir" "$node_dir" "$rg_dir"

tar -xzf "$NVIM_ARCHIVE" -C "$nvim_dir" --strip-components=1
tar -xJf "$NODE_ARCHIVE" -C "$node_dir" --strip-components=1

rg_stage=$(mktemp -d)
tar -xzf "$RG_ARCHIVE" -C "$rg_stage"
install -m 0755 \
  "$rg_stage/ripgrep-${RG_VERSION}-x86_64-unknown-linux-musl/rg" \
  "$rg_dir/rg"

"$nvim_dir/bin/nvim" --version
"$node_dir/bin/node" --version
"$rg_dir/rg" --version

ln -sfn /usr/bin/python3.12 "$HOME/bin/python3"
ln -sfn /usr/bin/python3.12 "$HOME/bin/python"
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

Switch the data and runtime symlinks:

```bash
data_link="$HOME/.local/share/nvim2"
data_next="$HOME/.local/share/.nvim2-next.$$"
nvim_next="$HOME/bin/.nvim-next.$$"
node_next="$HOME/bin/.node-next.$$"
rg_next="$HOME/bin/.rg-next.$$"

ln -s "$release_dir" "$data_next"
mv -Tf "$data_next" "$data_link"

ln -s "$nvim_dir/bin/nvim" "$nvim_next"
mv -Tf "$nvim_next" "$HOME/bin/nvim"

ln -s "$node_dir/bin/node" "$node_next"
mv -Tf "$node_next" "$HOME/bin/node"
for command in npm npx corepack; do
  command_next="$HOME/bin/.${command}-next.$$"
  ln -s "$node_dir/bin/$command" "$command_next"
  mv -Tf "$command_next" "$HOME/bin/$command"
done

ln -s "$rg_dir/rg" "$rg_next"
mv -Tf "$rg_next" "$HOME/bin/rg"
```

Validate immediately:

```bash
export PATH="$HOME/bin:$PATH"
python3 -c 'import sys; assert sys.version_info >= (3, 12), sys.version'
node -e 'process.exit(Number(process.versions.node.split(".")[0]) < 20)'
rg --version
bash "$HOME/.config/nvim2/tests/check.sh"
NVIM_APPNAME=nvim2 nvim
```

Do not run `Nvim2ToolsInstallSync`, `MasonUpdate`, `TSUpdate` or
`vim.pack.update()` on the restricted machine. Those are builder operations.

## Roll back

Stop Nvim2, restore the previous dotfiles commit and repoint the data and
runtime symlinks:

```bash
rollback_file="$HOME/.local/state/nvim2-release-rollback.env"
source "$rollback_file"

cd "$HOME/github.com/surbanski/dotfiles"
if [[ -n $PREVIOUS_COMMIT ]]; then
  git checkout --detach "$PREVIOUS_COMMIT"
fi

data_next="$HOME/.local/share/.nvim2-rollback.$$"
nvim_next="$HOME/bin/.nvim-rollback.$$"
node_next="$HOME/bin/.node-rollback.$$"
rg_next="$HOME/bin/.rg-rollback.$$"

if [[ -n $PREVIOUS_DATA ]]; then
  ln -s "$PREVIOUS_DATA" "$data_next"
  mv -Tf "$data_next" "$HOME/.local/share/nvim2"
fi

if [[ -n $PREVIOUS_NVIM ]]; then
  ln -s "$PREVIOUS_NVIM" "$nvim_next"
  mv -Tf "$nvim_next" "$HOME/bin/nvim"
fi

if [[ -n $PREVIOUS_NODE ]]; then
  previous_node_bin=$(dirname "$PREVIOUS_NODE")
  ln -s "$PREVIOUS_NODE" "$node_next"
  mv -Tf "$node_next" "$HOME/bin/node"
  for command in npm npx corepack; do
    command_next="$HOME/bin/.${command}-rollback.$$"
    ln -s "$previous_node_bin/$command" "$command_next"
    mv -Tf "$command_next" "$HOME/bin/$command"
  done
fi

if [[ -n $PREVIOUS_RG ]]; then
  ln -s "$PREVIOUS_RG" "$rg_next"
  mv -Tf "$rg_next" "$HOME/bin/rg"
fi

bash "$HOME/.config/nvim2/tests/check.sh"
```

Keep at least the current and previous release directories. Delete an old
release only after the replacement has been used successfully.

## Prepare upgrades on a trusted machine

An upgrade can change any of these layers:

| Layer | Version source |
| --- | --- |
| Neovim | `NVIM_VERSION` in `nvim2-release.env` |
| Node.js and builder npm | `NODE_VERSION` and `NPM_VERSION` in `nvim2-release.env` |
| Ripgrep | `RG_VERSION` in `nvim2-release.env` |
| Builder operating systems | image digests in `nvim2-release.env` |
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

When removing a package declaration, also run `:MasonUninstall PACKAGE` on the
development machine. The exact inventory check rejects undeclared packages.

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
installed parser. Remove it from a development machine with
`:lua require('nvim-treesitter').uninstall({ 'LANGUAGE' }):wait(120000)`, and
still build the final platform artifact from an empty data directory.

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

The profile keeps Kickstart's `PackChanged` block unchanged for easier upstream
merges, then clears its handler immediately afterward. This does not block
`vim.pack.update()`. It prevents plugin-controlled build steps and the
automatic `TSUpdate` action.

That is safe for the current plugin set:

- `telescope-fzf-native.nvim` is not installed;
- LuaSnip's optional `jsregexp` build is not used;
- parser installation is explicit through `Nvim2ToolsInstallSync`.

A future plugin that requires compilation or post-update generation will not
be ready automatically. Add an explicit reviewed build step to this release
process and test it in every platform image. Do not weaken hardening merely to
make a plugin install itself silently.

The clear happens immediately after Kickstart creates its handler. Add any
future approved `PackChanged` handler after that point.

## Validation scope

`tests/check.sh` is suitable for release validation and is inexpensive enough
to run after every accepted update. It rejects undeclared Mason packages and
parsers, checks every Mason launcher, starts the tools that expose a safe
version command, and exercises mappings, commands and several daily workflows.

The Amazon Linux 2023 path was tested end to end on 2026-08-12 with the public
`amazonlinux:2023` image, glibc 2.34, Python 3.12.13, Neovim 0.12.4, Node.js
22.23.2 and ripgrep 15.2.0. The connected builder produced 22 locked plugins,
27 pinned Mason packages and 21 parsers. A fresh `--network none` container
verified the artifact checksums, activated the release, passed `check.sh`, and
attached Pyright, Ruff, Bash, Terraform, YAML, Ansible, Helm and Docker
language servers. Treat these versions as a validation record, not hardcoded
upgrade values; the reviewed variables and configuration pins remain the
sources of truth.

Current limitations are:

- parser revisions and query completeness are not verified;
- CSS, JSON and YAML language-server launchers are checked but not started
  because their command-line entry points require an LSP transport;
- HTML attachment is exercised, but only a subset of other attached-LSP and
  formatter behavior is exercised;
- a plugin can have local modifications while retaining its locked Git commit.

Clean builders and the exact inventory checks prevent stale dependencies from
entering a release. Continue inspecting parser revision metadata and plugin
worktrees during review.
