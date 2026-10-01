# Dotfiles setup

The supported setup target is Linux x86-64 on Debian 13, Ubuntu 24.04,
Ubuntu 26.04 or Amazon Linux 2023. Run the scripts as the intended ordinary
user. Only `setup-system` uses `sudo`.

## Connected machine

Clone the repository, then run:

```bash
cd "$HOME/github.com/surbanski/dotfiles"
./setup-system
./setup-tools
./setup-asdf

for file in "$HOME/.bash_profile" "$HOME/.bashrc"; do
  if [[ -f $file && ! -L $file && ! -e $file.before-dotfiles && ! -L $file.before-dotfiles ]]; then
    mv -- "$file" "$file.before-dotfiles"
  fi
done
./bstow --dry-run -v -t "$HOME" stow \
  git tmux bash mc oh-my-posh k9s nvim2 gnupg codex
./bstow -v -t "$HOME" stow \
  git tmux bash mc oh-my-posh k9s nvim2 gnupg codex

source "$HOME/.bashrc"
hash -r
dotfiles-check
```

The setup sequence moves regular distribution-provided Bash startup files
aside without overwriting an existing backup. `bstow --dry-run` reports any
remaining conflict, including a foreign symlink.

`setup-tools` installs the selected daily tools from exact official release
files. `setup-asdf` installs the project runtimes in `versions.env`, pins each
plugin checkout and selects the first version in each list as the home default.
A project `.tool-versions` file continues to override those defaults.
An installation made by the immediately preceding `setup-asdf` layout can be
adopted only when its relative `asdf-VERSION` link is the current pin and its
executable is byte-for-byte equal to the executable extracted from the
checksum-verified official archive. Provider conflicts are checked before any
ownership state is written. Similar names, version output alone and modified
binaries are rejected without changing them.

## Complete offline release

For a restricted host, prefer the complete platform artifact over assembling
individual tool archives. It contains one immutable dotfiles snapshot together
with Neovim and its complete profile, Node.js, private standalone Python,
ripgrep, tmux and plugins, Oh My Posh, k9s, zoxide, kubectx, kubens, Task, fzf
and Terraform. Helm and kubectl deliberately remain separate setup choices.

The supported artifacts are `debian-13-x86_64`, `ubuntu-24.04-x86_64`,
`ubuntu-26.04-x86_64` and `amzn-2023-x86_64`. Build from a clean committed
checkout on a connected machine. Select the matching immutable image from
`dotfiles-release.env` and keep the checkout read-only in the builder:

```bash
set -euo pipefail
test -z "$(git status --porcelain --untracked-files=normal)"
source dotfiles-release.env
platform=debian-13-x86_64
image=$DEBIAN_13_IMAGE
output=${1:-"$PWD/offline-output"}
mkdir -p "$output"

docker pull "$image"
timeout --signal=TERM --kill-after=30s 5400s docker run --rm \
  --volume "$PWD:/workspace:ro" \
  --volume "$output:/out" \
  --env BUILDER_IMAGE="$image" \
  "$image" \
  bash /workspace/scripts/dotfiles-release \
    build "$platform" /workspace /out
```

The builder verifies every downloaded archive, compiles tmux against the
target distribution libraries, starts from empty Neovim data, and runs the
tool-enabled profile checks. The official Node archive initially contains its
upstream npm, then the builder installs the separately pinned and hashed npm
archive. The standalone CPython runtime contains the standard library but not
ansible-lint, yamllint or ansible-core. Separate generated hashed locks and a
complete wheelhouse supply those dependencies. The target installer creates
ordinary isolated venvs at their final retained paths using only those wheels.
It does not need sudo, a distribution Python, a compiler or network access.

The artifact contains a Git archive of the matching dotfiles commit, not the
main repository history. It also contains the full Neovim runtime tree, pinned
plugin Git metadata, parsers, queries, Mason receipts, tmux plugins, Python
locks and the temporary wheelhouse. `release.env`, `build-manifest.txt` and
`SHA256SUMS` record source identity, layout, versions, inputs and content.
After venv creation the retained installation removes the wheelhouse and
records a new local manifest covering file contents, modes and symlink targets.

Install the target distribution prerequisites while approved repositories are
available, then transfer the matching artifact. From the matching reviewed
dotfiles snapshot:

```bash
./setup-system --runtime
```

After disconnecting external networking, run the installer as the intended
ordinary user. It derives identity from that account and does not require a
particular user name, UID or `/home` path:

```bash
bash scripts/dotfiles-release install \
  "$PWD/dotfiles-COMMIT12-debian-13-x86_64.tar.gz"
source "$HOME/.bashrc"
hash -r
dotfiles-release list
dotfiles-release health
```

Verify the trusted transfer checksum before installation:

```bash
sha256sum --check --strict \
  dotfiles-COMMIT12-debian-13-x86_64.tar.gz.sha256
```

The full qualification path runs the same install plus health in a fresh
runtime container with `--network none`:

```bash
bash scripts/dotfiles-release verify debian-13-x86_64 \
  "$PWD/dotfiles-COMMIT12-debian-13-x86_64.tar.gz"
```

Releases are retained under `~/dotfiles-releases/dotfiles-COMMIT12`.
`current` controls new processes and `previous` supports whole-unit rollback.
The first install records every managed entry and backs up an accepted prior
file, link or provider tree beside that entry as a private
`.dotfiles-release-backup-SHA256` path. Keeping the backup on the destination
filesystem avoids relying on a cross-filesystem rename. A conflicting
foreign link, a symlink parent or unproven tool/provider stops the install
before activation. Existing `setup-tools`, `bstow`, historical Nvim release and
clean pinned tmux plugin installations are migrated only when their records and
content prove ownership. Private k9s files, kubeconfig inputs and unrelated
tmux plugins are not touched.

Use the manager for every selection change:

```bash
dotfiles-release list
dotfiles-release health
dotfiles-release health dotfiles-COMMIT12
dotfiles-release rollback
dotfiles-release rollback dotfiles-COMMIT12
dotfiles-release uninstall
dotfiles-release uninstall dotfiles-INACTIVE12
```

`rollback` selects `previous`, or an explicit complete retained ID. With no
previous release it restores the baseline. Plain `uninstall` also restores the
baseline without deleting retained payloads. `uninstall ID` removes only an
inactive, locally unmodified payload. Close any process still using that ID
before removing it because the manager deliberately does not guess process
ownership or terminate applications. Run the retained
`dotfiles-COMMIT12/bin/dotfiles-release` directly after restoring a baseline
that did not contain the public manager link.

All manager operations share a non-blocking lock. A pending record lets the
next invocation recover an interrupted import, selection or baseline restore
before continuing the command that was requested. Recovery restores both
selection links and each recorded projection entry, verifies the saved
baseline identity and removes the journal only after the state is coherent.
If a user changed a managed path or an old four-column journal no longer has
its backup, the manager preserves the journal, backup and user data and reports
the exact conflicting path. Inspect that path and its adjacent backup, restore
the expected managed link or move the foreign data aside, then retry the same
manager command. Do not edit `current`, `previous`, `pending.env`, installed
files or generated manifests by hand, and do not use `sudo` to move a venv.

Stable public links contain `current` literally. The Nvim and tmux launchers
resolve one physical release when each process starts. After a switch, reload
Bash with `source "$HOME/.bashrc" && hash -r`; new shells and applications use
the new release, while an existing Nvim process and tmux server remain on their
old physical configuration and plugins. `prefix` + `Shift-R` reloads that
server's physical config through `source-file -F`; it does not switch an A
server to B. Finish or safely stop the old server before expecting a new one to
use the newly selected release.

Mutable Nvim state, including ShaDa, undo, project marks, Mini Visits and
Telescope history, stays under `XDG_STATE_HOME` or `~/.local/state/nvim2`.
The first activation copies legacy Mini Visits and Telescope files only when
the new destination is absent and preserves the source. zoxide data,
tmux-resurrect sessions, caches, kubeconfig and credentials also remain outside
the immutable payload. The Nvim launcher remembers the user's original
`XDG_CONFIG_HOME` and `XDG_DATA_HOME` before selecting physical release data.
An interactive terminal Bash restores those values before integrations start.
Direct Nvim jobs use an explicit `_ZO_DATA_DIR`, defaulting to the user's
original data home, so zoxide never writes into retained release data. Explicit
`_ZO_DATA_DIR`, paths with spaces, nested launches and another `NVIM_APPNAME`
remain supported.

The release does not own `~/bin/python`, `~/bin/python3`, Helm or kubectl.
`helm-ls` works through its embedded Helm libraries. Basic kubectx and kubens
operations work against a local kubeconfig, while cluster operations, external
authentication executables, `kubectx --shell` and the optional k9s helpers
still require the corresponding host tools and services. Do not run the
release Node/Terraform provider and an asdf provider for those same public
commands in one HOME.

The historical 2026-10-01 qualification of source commit
`d4536234f5730fdb0e1f43335f9e0d5c0e79e935` measured the following apparent
sizes with `du -sb`. It did not measure allocated filesystem blocks:

| Platform | Outer archive | Retained `du -sb` | Regular-file bytes |
| --- | ---: | ---: | ---: |
| Debian 13 | 483,095,534 B (460.72 MiB) | 1,628,221,711 B (1.516 GiB) | 1,628,205,324 B |
| Ubuntu 24.04 | 483,098,178 B (460.72 MiB) | 1,628,132,819 B (1.516 GiB) | 1,628,116,432 B |
| Ubuntu 26.04 | 483,173,129 B (460.79 MiB) | 1,628,365,783 B (1.517 GiB) | 1,628,349,396 B |
| Amazon Linux 2023 | 479,423,683 B (457.21 MiB) | 1,642,467,571 B (1.530 GiB) | 1,613,590,766 B |

The post-review qualification of source commit
`57d5a1aaad3878e964825f43d9342da946f475ce`, tree
`507f7bc0e8f64362013703a6bd90380dca13e778`, measured both apparent size and
allocated blocks on the Docker overlay filesystem:

| Platform | Outer A archive | Regular-file bytes | Apparent size | Allocated blocks |
| --- | ---: | ---: | ---: | ---: |
| Debian 13 | 483,131,912 B (460.75 MiB) | 1,628,324,530 B | 1,628,340,927 B (1.517 GiB) | 1,818,140,672 B (1.693 GiB) |
| Ubuntu 24.04 | 483,121,613 B (460.74 MiB) | 1,628,225,590 B | 1,628,241,979 B (1.516 GiB) | 1,818,042,368 B (1.693 GiB) |
| Ubuntu 26.04 | 483,213,756 B (460.83 MiB) | 1,628,458,552 B | 1,628,474,941 B (1.517 GiB) | 1,818,165,248 B (1.693 GiB) |
| Amazon Linux 2023 | 479,465,185 B (457.25 MiB) | 1,613,691,294 B | 1,642,568,099 B (1.530 GiB) | 1,803,411,456 B (1.680 GiB) |

After retaining both complete A and B releases, the corresponding release
store measurements were:

| Platform | Regular-file bytes | Apparent size | Allocated blocks |
| --- | ---: | ---: | ---: |
| Debian 13 | 3,256,654,783 B | 3,256,687,619 B (3.033 GiB) | 3,636,289,536 B (3.387 GiB) |
| Ubuntu 24.04 | 3,256,458,021 B | 3,256,490,841 B (3.033 GiB) | 3,636,097,024 B (3.386 GiB) |
| Ubuntu 26.04 | 3,257,018,226 B | 3,257,051,046 B (3.033 GiB) | 3,636,461,568 B (3.387 GiB) |
| Amazon Linux 2023 | 3,227,487,917 B | 3,285,253,857 B (3.060 GiB) | 3,606,958,080 B (3.359 GiB) |

On Debian, sampling every 0.2 seconds during the A to B upgrade observed a
peak of 3,276,613,163 apparent bytes (3.052 GiB) and 3,657,785,344 allocated
bytes (3.406 GiB). The two read-only input archives occupy another 966,274,252
bytes (921.51 MiB) outside the release store. Combining those inputs with the
measured allocated peak gives 4,624,059,596 bytes (4.306 GiB). Import staging
is created under the measured release store, so it is included when sampled
and must not be added a second time; no staging entry remained after success.
The fresh qualification had no retained legacy installation, which would be
an additional cost on an upgraded host.

The approximately 460 MiB archive is the whole offline release, not the
standalone Python archive. Archive sizes remain within the original 435-475
MiB estimate. Allocated retained sizes, unlike the earlier apparent-only
figures, are within the original 1.65-1.90 GiB estimate per release. Refresh
these measurements for a new source revision or changed payload.

The [Nvim2 offline notes](nvim2/.config/nvim2/offline-releases.md) describe the
editor-specific runtime, health checks and state behavior. `TOOL_UPDATES.md`
describes how a new source revision becomes a separately qualified immutable
release.

The direct kubectl and Helm route is an alternative for machines where asdf is
not appropriate. Do not install both providers in the same home:

```bash
./setup-tools kubectl helm
"$HOME/bin/kubectl-1.27.11" version --client
"$HOME/bin/helm-3.22.0" version --short
```

Versioned installations remain in `~/bin`. Canonical command links are
relative, so an older retained installation can be selected again by running
the setup command from the matching reviewed repository revision. The input
archive is not needed when its verified installation is already retained.

## Preparing files for a restricted machine

Run this on a connected Linux x86-64 machine from the repository root. It
downloads the exact files selected by `versions.env` and `validation.env` into
the layout consumed by `setup-tools --from`.

```bash
set -euo pipefail
source validation.env
source versions.env
archive_root=${1:-"$HOME/tool-archives"}

download() {
  name=$1
  version=$2
  asset=$3
  url=$4
  digest=$5
  destination="$archive_root/$name/$version/$asset"
  mkdir -p "$(dirname -- "$destination")"
  if [[ ! -f $destination ]]; then
    temporary="$destination.part"
    curl --fail --location --silent --show-error \
      --connect-timeout 15 --max-time 300 --retry 2 \
      --output "$temporary" "$url"
    mv -- "$temporary" "$destination"
  fi
  printf '%s  %s\n' "$digest" "$destination" |
    sha256sum --check --strict
}

download gh "$GH_VERSION" "gh_${GH_VERSION}_linux_amd64.tar.gz" \
  "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" "$GH_SHA256"
download kyverno "$KYVERNO_VERSION" "kyverno-cli_v${KYVERNO_VERSION}_linux_x86_64.tar.gz" \
  "https://github.com/kyverno/kyverno/releases/download/v${KYVERNO_VERSION}/kyverno-cli_v${KYVERNO_VERSION}_linux_x86_64.tar.gz" "$KYVERNO_SHA256"
download task "$TASK_VERSION" task_linux_amd64.tar.gz \
  "https://github.com/go-task/task/releases/download/v${TASK_VERSION}/task_linux_amd64.tar.gz" "$TASK_SHA256"
download trivy "$TRIVY_VERSION" "trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" \
  "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" "$TRIVY_SHA256"
download k9s "$K9S_VERSION" k9s_Linux_amd64.tar.gz \
  "https://github.com/derailed/k9s/releases/download/v${K9S_VERSION}/k9s_Linux_amd64.tar.gz" "$K9S_SHA256"
download kubeconform "$KUBECONFORM_VERSION" kubeconform-linux-amd64.tar.gz \
  "https://github.com/yannh/kubeconform/releases/download/v${KUBECONFORM_VERSION}/kubeconform-linux-amd64.tar.gz" "$KUBECONFORM_SHA256"
download shellcheck "$SHELLCHECK_VERSION" "shellcheck-v${SHELLCHECK_VERSION}.linux.x86_64.tar.xz" \
  "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.linux.x86_64.tar.xz" "$SHELLCHECK_SHA256"
download oh-my-posh "$OMP_VERSION" posh-linux-amd64 \
  "https://github.com/JanDeDobbeleer/oh-my-posh/releases/download/v${OMP_VERSION}/posh-linux-amd64" "$OMP_SHA256"
download kubectx "$KUBECTX_VERSION" "kubectx_v${KUBECTX_VERSION}_linux_x86_64.tar.gz" \
  "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX_VERSION}/kubectx_v${KUBECTX_VERSION}_linux_x86_64.tar.gz" "$KUBECTX_SHA256"
download kubens "$KUBECTX_VERSION" "kubens_v${KUBECTX_VERSION}_linux_x86_64.tar.gz" \
  "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX_VERSION}/kubens_v${KUBECTX_VERSION}_linux_x86_64.tar.gz" "$KUBENS_SHA256"
download rg "$RG_VERSION" "ripgrep-${RG_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
  "https://github.com/BurntSushi/ripgrep/releases/download/${RG_VERSION}/ripgrep-${RG_VERSION}-x86_64-unknown-linux-musl.tar.gz" "$RG_SHA256"
download zoxide "$ZOXIDE_VERSION" "zoxide-${ZOXIDE_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
  "https://github.com/ajeetdsouza/zoxide/releases/download/v${ZOXIDE_VERSION}/zoxide-${ZOXIDE_VERSION}-x86_64-unknown-linux-musl.tar.gz" "$ZOXIDE_SHA256"
download uv "$UV_VERSION" uv-x86_64-unknown-linux-gnu.tar.gz \
  "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz" "$UV_SHA256"
download nvim "$NVIM_VERSION" nvim-linux-x86_64.tar.gz \
  "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-linux-x86_64.tar.gz" "$NVIM_SHA256"

for version in "${KUBECTL_VERSIONS[@]}"; do
  download kubectl "$version" kubectl \
    "https://dl.k8s.io/release/v${version}/bin/linux/amd64/kubectl" \
    "${KUBECTL_SHA256_BY_VERSION[$version]}"
done
for version in "${HELM_VERSIONS[@]}"; do
  download helm "$version" "helm-v${version}-linux-amd64.tar.gz" \
    "https://get.helm.sh/helm-v${version}-linux-amd64.tar.gz" \
    "${HELM_SHA256_BY_VERSION[$version]}"
done
```

Copy the directory without extracting or repacking its files. On the target,
install system packages while the approved repositories are reachable. After
external access is disabled, import the copied files:

```bash
cd "$HOME/github.com/surbanski/dotfiles"
./setup-system

./setup-tools --from "$HOME/tool-archives" \
  gh kyverno task trivy k9s kubeconform shellcheck oh-my-posh \
  kubectx kubens rg zoxide uv nvim kubectl helm

for file in "$HOME/.bash_profile" "$HOME/.bashrc"; do
  if [[ -f $file && ! -L $file && ! -e $file.before-dotfiles && ! -L $file.before-dotfiles ]]; then
    mv -- "$file" "$file.before-dotfiles"
  fi
done
./bstow --dry-run -v -t "$HOME" stow \
  git tmux bash mc oh-my-posh k9s nvim2 gnupg codex
./bstow -v -t "$HOME" stow \
  git tmux bash mc oh-my-posh k9s nvim2 gnupg codex
source "$HOME/.bashrc"
hash -r
dotfiles-check
```

This importer does not use `curl`, package managers, asdf or source builds.
Missing files are reported as
`DIR/NAME/VERSION/UPSTREAM_ASSET`. It installs the complete Neovim runtime tree,
but it does not include the Nvim2 plugins, Mason packages, parsers or Node
runtime. Use the complete dotfiles release procedure for an offline editor.

Terraform and Terragrunt remain asdf-managed. A restricted machine can install
them only when the pinned plugins and their real release sources are reachable.
No generic offline asdf transport is provided. `htop` remains an operating
system package, and Go is not a setup dependency.

## Prepared runtime data

Executable installation does not provide service credentials, cluster data,
vulnerability databases or package indexes. Prepare these on a connected
machine and copy them separately.

For Trivy, populate all data needed by version 0.74.0:

```bash
trivy image --cache-dir "$HOME/trivy-cache" --download-db-only
trivy image --cache-dir "$HOME/trivy-cache" --download-java-db-only
trivy config --cache-dir "$HOME/trivy-cache" ./local-config-fixtures
```

Record `db/metadata.json`, `java-db/metadata.json` and
`policy/metadata.json`, including their update and download times. A restricted
filesystem scan uses the prepared data without disabling vulnerability checks:

```bash
trivy filesystem --cache-dir "$HOME/trivy-cache" --scanners vuln \
  --skip-db-update --skip-java-db-update --skip-check-update \
  --offline-scan ./local-filesystem-fixture
trivy config --cache-dir "$HOME/trivy-cache" --skip-check-update \
  ./local-config-fixtures
```

Prepare Kubernetes JSON schemas at an immutable source revision. Validate both
a known valid file and a deliberately invalid file. Add required CRD schemas
explicitly and do not use `-ignore-missing-schemas`:

```bash
kubeconform -strict \
  -schema-location "$HOME/kube-schemas/{{ .ResourceKind }}{{ .KindSuffix }}.json" \
  -schema-location "$HOME/kube-schemas/{{ .ResourceKind }}_{{ .ResourceAPIVersion }}.json" \
  ./manifests
```

Use local inputs for the remaining checks:

```bash
helm template local ./chart
kyverno apply ./policy.yaml --resource ./resource.yaml
KUBECONFIG="$HOME/disposable-kubeconfig" kubectx
KUBECONFIG="$HOME/disposable-kubeconfig" kubens NAMESPACE --force
uv venv --python /usr/bin/python3 "$HOME/offline-venv"
uv pip install --python "$HOME/offline-venv/bin/python" \
  --offline --no-index --find-links "$HOME/wheels" PACKAGE
uvx --offline --no-index --from "$HOME/wheels/TOOL.whl" TOOL
```

`gh auth status` distinguishes a working executable from GitHub API access.
K9s needs a reachable Kubernetes API and credentials for interactive use.
Remote Helm repositories, OCI registries and Kyverno image or cluster
operations need their own approved endpoints.

## Local Kubernetes helper inputs

`checkbackups` reads Kubernetes context names from
`~/kube-backup-contexts.txt`. `dumplogs` reads stable pod-name prefixes from
`~/kube-log-prefixes.txt`; do not put generated full pod names in this file.
Both files use the same format: one literal value per line. Blank lines and
full-line comments are ignored, surrounding whitespace and CRLF are accepted,
and duplicates keep their first position. Values are never evaluated as shell
code or split into extra command arguments.

Example contexts:

```bash
cat >"$HOME/kube-backup-contexts.txt" <<'EOF'
# Personal test clusters
development
staging
EOF
```

Example stable pod prefixes:

```bash
cat >"$HOME/kube-log-prefixes.txt" <<'EOF'
# Application pod prefixes
api-
worker-
EOF
```

These files are private operational inputs. Setup and `bstow` do not create,
move or replace them. `checkbackups` needs `kubectl` and `jq`; it queries each
context with `--context` and leaves the current context unchanged. `dumplogs`
needs `kubectl`, queries the current namespace once, and accepts an optional
duration such as `dumplogs 30m`. It writes completed downloads under a
timestamped `*_kubernetes-logs` directory and returns nonzero if any selected
pod fails.

`findpodsonnodepool LABEL_SELECTOR` lists pods on matching nodes without
changing context. `curr` prints the current context and namespace.
`postgres-db-list` uses the current `psql` connection settings and returns a
JSON array of database names. `day` stores daily notes under
`$NOTES/periodic-notes/daily-notes`, falling back to `SECOND_BRAIN` for older
private configuration, and opens them with Nvim2.

## TPM and Krew

TPM and its plugin checkouts use the commits in `versions.env`. This section is
only for the connected setup. Complete offline releases do not bundle or run
TPM; their tmux config loads sensible, resurrect and continuum directly from
the physical release. On a connected machine, reconcile the managed checkouts
with:

```bash
set -euo pipefail
. ./versions.env
plugins=$HOME/.tmux/plugins
mkdir -p "$plugins"

install_tmux_plugin() {
  name=$1
  url=$2
  commit=$3
  destination=$plugins/$name
  if [[ ! -d $destination/.git ]]; then
    git clone "$url" "$destination"
  fi
  [[ $(git -C "$destination" remote get-url origin) == "$url" ]]
  git -C "$destination" fetch --depth 1 origin "$commit"
  git -C "$destination" reset --hard "$commit"
  git -C "$destination" clean -fdx
  [[ $(git -C "$destination" rev-parse HEAD) == "$commit" ]]
}

install_tmux_plugin tpm https://github.com/tmux-plugins/tpm.git \
  "$TPM_COMMIT"
install_tmux_plugin tmux-sensible \
  https://github.com/tmux-plugins/tmux-sensible.git \
  "$TMUX_SENSIBLE_COMMIT"
install_tmux_plugin tmux-resurrect \
  https://github.com/tmux-plugins/tmux-resurrect.git \
  "$TMUX_RESURRECT_COMMIT"
install_tmux_plugin tmux-continuum \
  https://github.com/tmux-plugins/tmux-continuum.git \
  "$TMUX_CONTINUUM_COMMIT"
```

This resets only the four managed plugin checkouts. Session data under
`~/.tmux/resurrect` remains intact. On a restricted machine, transfer the
complete pinned directories under `~/.tmux/plugins` before starting tmux.

Krew remains separate from the binary importer. Download
`krew-linux_amd64.tar.gz` for `KREW_VERSION`, verify `KREW_SHA256`, extract
`krew-linux_amd64`, then install the manager:

```bash
set -euo pipefail
. ./versions.env
archive=$(mktemp)
work=$(mktemp -d)
trap 'rm -f "$archive"; rm -rf "$work"' EXIT
curl --fail --location --retry 3 --connect-timeout 15 \
  --max-time 300 --output "$archive" \
  "https://github.com/kubernetes-sigs/krew/releases/download/v${KREW_VERSION}/krew-linux_amd64.tar.gz"
printf '%s  %s\n' "$KREW_SHA256" "$archive" | sha256sum -c -
tar -xzf "$archive" -C "$work"
"$work/krew-linux_amd64" install krew
"$HOME/.krew/bin/kubectl-krew" version
```

Install and pin needed kubectl plugins through Krew. For a restricted machine,
transfer the manager and each complete plugin installation; a copied kubectl
executable does not include plugins.

## Validation

Run the repository checks through Task:

```bash
bash scripts/install-validation-tool task
.cache/validation-tools/bin/task validate
```

Repository-owned shell sources are linted from their real checked-in paths.
The Bash startup also conditionally loads distribution-owned Midnight
Commander, bash-completion and fzf files. Their paths differ by supported
platform, so each distribution qualification uses the actual packaged files
and exercises startup there; upstream package contents are not copied into the
repository or replaced with empty lint fixtures. Generated Python and uv
activation scripts are exercised in isolated prompt tests.

`~/.fzf.bash` and `~/.extras` are optional private inputs outside repository
static analysis. The supported contract is that they are loaded only when
present and that a load failure emits a warning without aborting startup. Their
contents remain the user's responsibility.

Workflow validation runs locally without GitHub credentials. Set `GH_TOKEN`,
`GITHUB_TOKEN` or use an active `gh` login to additionally enable Zizmor's
online audits. The GitHub Actions workflow supplies its repository token.
