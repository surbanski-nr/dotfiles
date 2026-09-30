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
nvim2-release
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

Verify the outer archive digest recorded by the release service. Extract it,
enter the artifact directory and run the installer shipped in that artifact:

```bash
cd /path/to/platform-artifact
sha256sum --check --strict SHA256SUMS
bash ./nvim2-release install "$PWD"
```

The installer validates all checksums, release identity, OS, architecture,
HOME, UID and Python ABI. It extracts Neovim, Node.js, ripgrep and Nvim2 data
into hidden staging paths on the target filesystem, validates the staged
executables and configuration, and runs a `bstow` dry run before changing any
active path. An existing versioned destination is reused only when it exactly
matches the staged content. A differing destination, regular executable,
unknown link or unknown configuration source is a conflict.

After the full preflight, the installer promotes new versioned paths, records
the previous complete set in mode-0600 state and atomically switches the
configuration, data and executable links. It runs the tool-enabled Nvim2 check
after activation. Any activation or check failure restores the previous set
and removes staging and newly promoted paths. Repeating the command for an
already active release is safe. A plugin-only release can reuse byte-identical
runtime versions without extracting over them.

Older managed releases may keep executable roots under `~/.local/opt`. Their
recorded link targets remain valid during migration; do not delete them until
the new release and rollback have both passed.

## Roll back

Stop all Nvim2 processes, then use the script from the active artifact or its
matching retained repository:

The release switch replaces configuration and `~/.local/share/nvim2`, but it
does not replace `~/.local/state/nvim2`. That retained state contains ShaDa,
persistent undo and `project-marks/`. Back it up with the rollback record when
the host backup policy does not already cover `~/.local/state`; never package
a developer's project marks into a release artifact.

```bash
bash ./nvim2-release rollback
```

Rollback first verifies that every active path still belongs to the recorded
release. It then restores the matching configuration, data and all runtime
links as one set. A regular data directory imported by the first installation
is restored as a regular directory, not converted permanently into a link. Do
not roll back only the editor binary against newer plugin or Mason data.

Repeat the full offline check and representative editing. Keep both releases
until that verification succeeds. There is no purge command.
