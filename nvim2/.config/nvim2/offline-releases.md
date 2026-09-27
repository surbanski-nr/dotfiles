# Nvim2 offline releases

An offline Nvim2 release is one unit containing the matching dotfiles commit,
Neovim, Node.js, ripgrep, locked plugins, Mason packages, Treesitter parsers and
queries. Do not update one of those parts independently on a restricted host.

## Supported matrix

`nvim2-release.env` pins every builder image by digest and records each target
identity explicitly.

| Platform | User | Home | Python source |
| --- | --- | --- | --- |
| Debian 13 x86-64 | `surbanski` | `/home/surbanski` | Debian 13 packages |
| Ubuntu 24.04 x86-64 | `surbanski` | `/home/surbanski` | Ubuntu 24.04 packages |
| Ubuntu 26.04 x86-64 | `surbanski` | `/home/surbanski` | Ubuntu 26.04 packages |
| Amazon Linux 2023 x86-64 | `ec2-user` | `/home/ec2-user` | Amazon Linux 2023 packages |

Mason Python environments contain absolute interpreter and home paths. The
artifact therefore records and validates the interpreter's resolved path and
major/minor version as well as the operating system, architecture, UID and
home. The Python in this artifact is the distro runtime. It is separate from a
project Python selected through asdf.

## Build locally

Build only from a clean commit. The release tag must be
`nvim2-<7-to-40-character lowercase commit prefix>` and resolve to that commit.
Use [TOOL_UPDATES.md](../../../TOOL_UPDATES.md) for uncommitted experiments.

```bash
test -z "$(git status --porcelain --untracked-files=normal)"
source nvim2-release.env
commit=$(git rev-parse HEAD)
tag="nvim2-$commit"
output="$HOME/nvim2-builder-output"
mkdir -p "$output"

platform=debian-13-x86_64
image=$DEBIAN_13_IMAGE
docker pull "$image"
timeout --signal=TERM --kill-after=30s 3600s docker run --rm \
  --volume "$PWD:/workspace:ro" \
  --volume "$output:/out" \
  --env RELEASE_TAG="$tag" \
  --env SOURCE_COMMIT="$commit" \
  --env BUILDER_IMAGE="$image" \
  "$image" \
  bash /workspace/scripts/nvim2-release \
    build "$platform" /workspace /out
```

Repeat the command with these platform and image pairs:

```text
debian-13-x86_64       DEBIAN_13_IMAGE
ubuntu-24.04-x86_64    UBUNTU_2404_IMAGE
ubuntu-26.04-x86_64    UBUNTU_2604_IMAGE
amzn-2023-x86_64       AMZN_2023_IMAGE
```

The script installs target packages, creates the exact user, downloads and
checks pinned release files, builds Nvim2 data from empty storage, runs the
tool-enabled check and creates one artifact directory. It uses this layout:

```text
~/bin/nvim -> nvim-VERSION/bin/nvim
~/bin/node -> nodejs-VERSION/bin/node
~/bin/rg -> rg-VERSION
```

On Amazon Linux 2023 only, the builder compiles the pinned Tree-sitter CLI
because Mason's upstream executable requires a newer glibc. The compiler,
Cargo and its staging directory do not belong to the runtime artifact. Go is
not installed or required on any target.

## Verify without network access

Prepare the runtime image while connected, then commit it and launch a new
container with networking disabled. This checks the network boundary itself.

```bash
runtime_container="nvim2-runtime-$platform"
runtime_image="nvim2-runtime:$platform"
artifact="$output/$platform"

docker run --detach --name "$runtime_container" "$image" sleep infinity
docker cp scripts/nvim2-release \
  "$runtime_container:/usr/local/bin/nvim2-release"
timeout --signal=TERM --kill-after=15s 600s docker exec \
  --env TARGET_HOME="$TARGET_HOME" \
  --env TARGET_UID="$TARGET_UID" \
  --env TARGET_USER="$TARGET_USER" \
  "$runtime_container" \
  bash /usr/local/bin/nvim2-release prepare-runtime "$platform"
docker commit "$runtime_container" "$runtime_image"
docker rm "$runtime_container"

timeout --signal=TERM --kill-after=30s 900s docker run --rm \
  --network none \
  --volume "$artifact:/artifact:ro" \
  "$runtime_image" \
  bash /usr/local/bin/nvim2-release verify "$platform" /artifact
```

Set `TARGET_USER`, `TARGET_UID` and `TARGET_HOME` from the matching variables in
`nvim2-release.env`. Verification checks every checksum before extraction and
fails on a wrong platform, architecture, user, UID, home, Python path, Python
major/minor version or source commit. It also checks that external DNS is not
available, then runs the complete Nvim2 test with tools enabled.

The artifact contains:

```text
SHA256SUMS
build-manifest.txt
dotfiles.bundle
node-vVERSION-linux-x64.tar.xz
nvim-linux-x86_64.tar.gz
nvim2-data.tar.gz
os-packages.txt
release.env
ripgrep-VERSION-x86_64-unknown-linux-musl.tar.gz
```

Review `build-manifest.txt`, `os-packages.txt`, all check output, and the
captured health evidence described in [TOOL_UPDATES.md](../../../TOOL_UPDATES.md).
Open representative Python, Lua, Bash, TypeScript/TSX, Terraform, Ansible, Helm
and YAML files before accepting the release.

## GitHub Actions

The `Build Nvim2 offline release` workflow checks out the release commit and
builds missing artifacts for all four platforms. It uploads directly to an
existing draft release. It does not create or publish a release.

Creating a tag or release is an explicitly authorized publishing operation.
When authorized, create the draft for the reviewed clean commit:

```bash
commit=$(git rev-parse HEAD)
tag="nvim2-$commit"
gh release create "$tag" \
  --target "$commit" \
  --draft \
  --title "$commit" \
  --notes "Offline Nvim2 release for $commit"
```

The tag starts the workflow. A manual retry can build only missing assets, or
replace all four while the release is still a draft:

```bash
gh workflow run nvim2-release.yml \
  --ref main \
  -f release_tag="$tag" \
  -f force=false
```

Use `force=true` only after reviewing why an existing draft asset must be
replaced. Published immutable assets are not rewritten. The expected names are:

```text
nvim2-offline-debian-13-x86_64.tar.gz
nvim2-offline-ubuntu-24.04-x86_64.tar.gz
nvim2-offline-ubuntu-26.04-x86_64.tar.gz
nvim2-offline-amzn-2023-x86_64.tar.gz
```

## Install on a restricted machine

Install operating-system runtime packages from approved repositories while
they are reachable. Transfer the matching artifact, then disconnect external
networking. Stop all Nvim2 processes before activation.

Verify the outer archive digest recorded by the release service. After
extracting it, verify its internal files and identity:

```bash
cd /path/to/platform-artifact
sha256sum --check --strict SHA256SUMS
source ./release.env
test "$HOME" = "$TARGET_HOME"
test "$(id -u)" = "$TARGET_UID"
test "$(uname -m)" = x86_64
test "$(readlink -f "$(command -v python3)")" = "$PYTHON_PATH"
test "$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')" = \
  "$PYTHON_VERSION"
```

Preserve the current paths for rollback, and keep an existing regular data
directory as its own retained release:

```bash
mkdir -p "$HOME/.local/share/nvim2-releases" "$HOME/.local/state"
if [[ -d "$HOME/.local/share/nvim2" && ! -L "$HOME/.local/share/nvim2" ]]; then
  imported="$HOME/.local/share/nvim2-releases/imported-$(date -u +%Y%m%d-%H%M%S)"
  mv "$HOME/.local/share/nvim2" "$imported"
  ln -s "$imported" "$HOME/.local/share/nvim2"
fi

record_target() {
  if [[ -L $1 ]]; then
    readlink -f -- "$1"
  elif [[ -e $1 ]]; then
    printf 'refusing unmanaged path: %s\n' "$1" >&2
    return 1
  else
    printf 'ABSENT\n'
  fi
}

previous_init=$(record_target "$HOME/.config/nvim2/init.lua")
case $previous_init in
  ABSENT) previous_repo=ABSENT ;;
  */nvim2/.config/nvim2/init.lua)
    previous_repo=${previous_init%/nvim2/.config/nvim2/init.lua}
    ;;
  *) printf 'unknown Nvim2 configuration source: %s\n' "$previous_init" >&2; exit 1 ;;
esac

rollback_file="$HOME/.local/state/nvim2-release-rollback.env"
printf '%s\n' \
  "PREVIOUS_DATA=$(printf %q "$(record_target "$HOME/.local/share/nvim2")")" \
  "PREVIOUS_NVIM=$(printf %q "$(record_target "$HOME/bin/nvim")")" \
  "PREVIOUS_NODE=$(printf %q "$(record_target "$HOME/bin/node")")" \
  "PREVIOUS_NPM=$(printf %q "$(record_target "$HOME/bin/npm")")" \
  "PREVIOUS_NPX=$(printf %q "$(record_target "$HOME/bin/npx")")" \
  "PREVIOUS_COREPACK=$(printf %q "$(record_target "$HOME/bin/corepack")")" \
  "PREVIOUS_RG=$(printf %q "$(record_target "$HOME/bin/rg")")" \
  "PREVIOUS_REPO=$(printf %q "$previous_repo")" \
  >"$rollback_file"
```

Extract each component to a new versioned path. Clone the matching commit from
the bundle and use `bstow` for the Nvim2 configuration:

```bash
nvim_dir="$HOME/bin/nvim-$NVIM_VERSION"
node_dir="$HOME/bin/nodejs-$NODE_VERSION"
rg_path="$HOME/bin/rg-$RG_VERSION"
release_dir="$HOME/.local/share/nvim2-releases/$RELEASE_ID"
repo="$HOME/github.com/surbanski/dotfiles-$DOTFILES_COMMIT"

mkdir -p "$nvim_dir" "$node_dir" "$release_dir" "$(dirname "$repo")"
tar -xzf "$NVIM_ARCHIVE" -C "$nvim_dir" --strip-components=1
tar -xJf "$NODE_ARCHIVE" -C "$node_dir" --strip-components=1
rg_stage=$(mktemp -d)
tar -xzf "$RG_ARCHIVE" -C "$rg_stage"
install -m 0755 \
  "$rg_stage/ripgrep-${RG_VERSION}-x86_64-unknown-linux-musl/rg" "$rg_path"
find "$rg_stage" -depth -delete
tar -xzf nvim2-data.tar.gz -C "$release_dir"
git clone dotfiles.bundle "$repo"
git -C "$repo" checkout --detach "$DOTFILES_COMMIT"
(
  cd "$repo"
  ./bstow --dry-run --force -t "$HOME" stow nvim2
  ./bstow --force -t "$HOME" stow nvim2
)
printf 'CURRENT_REPO=%q\n' "$repo" >>"$rollback_file"
```

Check the extracted executables directly before switching any canonical link:

```bash
"$nvim_dir/bin/nvim" --version
"$node_dir/bin/node" --version
"$rg_path" --version
test -x "$release_dir/mason/bin/lua-language-server"
```

Activate with temporary relative links and atomic renames. Existing links must
point to known managed versioned paths. Do not replace a regular file or an
unknown link.

```bash
cd "$HOME/bin"
ln -s "nvim-$NVIM_VERSION/bin/nvim" .nvim.release
ln -s "nodejs-$NODE_VERSION/bin/node" .node.release
ln -s "nodejs-$NODE_VERSION/bin/npm" .npm.release
ln -s "nodejs-$NODE_VERSION/bin/npx" .npx.release
ln -s "nodejs-$NODE_VERSION/bin/corepack" .corepack.release
ln -s "rg-$RG_VERSION" .rg.release
mv -T .nvim.release nvim
mv -T .node.release node
mv -T .npm.release npm
mv -T .npx.release npx
mv -T .corepack.release corepack
mv -T .rg.release rg
cd "$HOME/.local/share"
ln -s "nvim2-releases/$RELEASE_ID" .nvim2.release
mv -T .nvim2.release nvim2
hash -r
NVIM_APPNAME=nvim2 "$HOME/bin/nvim" --headless '+qa'
NVIM2_CHECK_TOOLS=1 bash "$HOME/.config/nvim2/tests/check.sh"
```

Older managed releases may keep executable roots under `~/.local/opt`. Their
recorded link targets remain valid during migration; do not delete them until
the new release and rollback have both passed.

## Roll back

Stop all Nvim2 processes. Source the saved rollback file, verify every target
exists, and atomically restore the complete set of links. Restore the matching
dotfiles commit as well. Do not roll back only the editor binary against newer
plugin or Mason data.

The release switch replaces configuration and `~/.local/share/nvim2`, but it
does not replace `~/.local/state/nvim2`. That retained state contains ShaDa,
persistent undo and `project-marks/`. Back it up with the rollback record when
the host backup policy does not already cover `~/.local/state`; never package
a developer's project marks into a release artifact.

```bash
source "$HOME/.local/state/nvim2-release-rollback.env"
for target in "$PREVIOUS_DATA" "$PREVIOUS_NVIM" "$PREVIOUS_NODE" \
  "$PREVIOUS_NPM" "$PREVIOUS_NPX" "$PREVIOUS_COREPACK" "$PREVIOUS_RG"; do
  [[ $target == ABSENT || -e $target ]]
done
[[ $PREVIOUS_REPO == ABSENT || -x $PREVIOUS_REPO/bstow ]]

restore_link() {
  local link=$1 target=$2 temporary=$3 relative
  if [[ $target == ABSENT ]]; then
    unlink "$link"
    return
  fi
  relative=$(realpath --relative-to="$(dirname "$link")" "$target")
  ln -s "$relative" "$temporary"
  mv -T "$temporary" "$link"
}

cd "$HOME/.local/share"
restore_link "$HOME/.local/share/nvim2" "$PREVIOUS_DATA" .nvim2.rollback
cd "$HOME/bin"
restore_link "$HOME/bin/nvim" "$PREVIOUS_NVIM" .nvim.rollback
restore_link "$HOME/bin/node" "$PREVIOUS_NODE" .node.rollback
restore_link "$HOME/bin/npm" "$PREVIOUS_NPM" .npm.rollback
restore_link "$HOME/bin/npx" "$PREVIOUS_NPX" .npx.rollback
restore_link "$HOME/bin/corepack" "$PREVIOUS_COREPACK" .corepack.rollback
restore_link "$HOME/bin/rg" "$PREVIOUS_RG" .rg.rollback
(
  cd "$CURRENT_REPO"
  ./bstow -t "$HOME" unstow nvim2
)
if [[ $PREVIOUS_REPO != ABSENT ]]; then
  (
    cd "$PREVIOUS_REPO"
    ./bstow --force -t "$HOME" stow nvim2
  )
fi
hash -r
```

Repeat the full offline check and representative editing. Keep both releases
until that verification succeeds. There is no purge command.
