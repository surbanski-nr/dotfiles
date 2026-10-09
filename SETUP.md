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
# Optional online project runtimes:
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

`versions.env` stores direct releases in `TOOL_RELEASES`. Each tool has ordered
`version|full_URL|SHA256` records, and the first record is the default. A
required default without an artifact is an error, with no fallback to a later
record. `validation.env` uses the same record format in
`VALIDATION_RELEASES`, and `VALIDATION_TOOLS` is the installer's authoritative
tool list. Task exists only there. Daily ShellCheck, validation ShellCheck and
Mason ShellCheck remain independent pins.

`setup-tools` downloads and installs the selected daily tools from these exact
official release records. It supports only connected installation; offline
deployment uses the complete release described below. Optional online
`setup-asdf` reads runtime versions from the same catalog, but plugin repository
and commit data from `ASDF_PLUGINS`; plugin downloads and
verification remain asdf's responsibility. It selects the first version for
each runtime as the home default. A project `.tool-versions` file continues to
override those defaults.
An installation made by the immediately preceding `setup-asdf` layout can be
adopted only when its relative `asdf-VERSION` link is the current pin and its
executable is byte-for-byte equal to the executable extracted from the
checksum-verified official archive. Provider conflicts are checked before any
ownership state is written. Similar names, version output alone and modified
binaries are rejected without changing them.

Edit OS package lists and their expected commands in `system.env`. Common
runtime packages are included in every role; build and connected roles add
their own common and distribution-specific packages. These packages have no
version pins and use the current apt/dnf repository candidates. The same file
lists commands each connected entry point requires before installation.
Package names and command names are separate, since packages such as
`diffutils` provide commands such as `cmp`. Amazon Linux's full GnuPG swap
remains part of the connected installation procedure.

`probes.env` owns tool version arguments shared by `setup-tools` and release
health. Each value contains whitespace-separated arguments; omitted tools use
`--version`. The builder embeds this data in the generated standalone manager,
so it works outside the checkout and can check older releases that did not
include the shared configuration file. Edit the source configuration and
rebuild; do not edit generated managers.

The direct kubectl and Helm route is an online alternative for machines where
asdf is not appropriate. Do not install both providers in the same home:

```bash
./setup-tools kubectl helm
"$HOME/bin/kubectl-1.27.11" version --client
"$HOME/bin/helm-3.22.0" version --short
```

Versioned installations remain in `~/bin`. Canonical command links are
relative, so an older retained installation can be selected again by running
the setup command from the matching reviewed repository revision. An intact
retained installation is reused without downloading it again.
Terraform and Terragrunt use optional `setup-asdf` in this connected flow.
`htop` remains an operating-system package, and Go is not a setup dependency.

## Complete offline release

For a restricted host, use the complete platform artifact. This is the only
supported offline installation route; `setup-tools` and `setup-asdf` are not
used. The artifact contains one immutable dotfiles snapshot together
with Neovim and its complete profile, Node.js, private standalone Python,
ripgrep, tmux and plugins, Oh My Posh, k9s, zoxide, kubectx, kubens, Task, fzf
and Terraform, plus every kubectl and Helm version listed in `versions.env`.
Each release owns its complete tool payload, even when another retained release
contains the same versions. Asdf, its plugins and its shims are not part of the
offline package. Optional online `setup-asdf` remains available independently.

The supported artifacts are `debian-13-x86_64`, `ubuntu-24.04-x86_64`,
`ubuntu-26.04-x86_64` and `amzn-2023-x86_64`. Build from a clean committed
checkout on a connected machine. Select the matching immutable image from
`release.env` and keep the checkout read-only in the builder:

```bash
set -euo pipefail
test -z "$(git status --porcelain --untracked-files=normal)"
source release.env
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
  bash /workspace/scripts/build-dotfiles-release \
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

`scripts/build-dotfiles-release` is the connected build and runtime-image
preparation entry point. `scripts/dotfiles-release` is the standalone manager
shipped inside each archive. The manager verifies, installs, lists, checks,
rolls back and uninstalls releases without the builder or a Git checkout.

The artifact contains a Git archive of the matching dotfiles commit, not the
main repository history. It also contains the full Neovim runtime tree, pinned
plugin Git metadata, parsers, queries, Mason receipts, tmux plugins, Python
locks and the temporary wheelhouse. `release.env`, `build-manifest.txt` and
`SHA256SUMS` record source identity, layout, versions, inputs and content.
The generated payload-root `release.env` is distinct from the checked-in
`dotfiles/release.env`, which contains builder image pins.
After venv creation the retained installation removes the wheelhouse and
records a new local manifest covering file contents, modes and symlink targets.

Install the target distribution prerequisites while approved repositories are
available, then transfer the matching artifact. From the matching reviewed
dotfiles snapshot:

```bash
./setup-system --offline-release
```

This flag installs only the release's system prerequisites, not its bundled
tools. It still needs access to apt/dnf repositories. The default invocation
without a flag prepares a connected setup instead.

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
before activation. Existing `setup-tools`, `bstow` and clean pinned tmux plugin
installations are migrated only when their records and content prove ownership.
Private k9s files, kubeconfig inputs and unrelated tmux plugins are not touched.

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
If a user changed a managed path or a backup no longer matches its recorded
identity, the manager preserves the journal, backup and user data and reports
the exact conflicting path. Inspect that path and its adjacent backup, restore
the expected managed link or move the foreign data aside, then retry the same
manager command. Do not edit `current`, `previous`, `pending.env`, installed
files or generated manifests by hand, and do not use `sudo` to move a venv.

Stable public links contain `current` literally. The Nvim, tmux and Kubernetes
client launchers resolve one physical release when each process starts. After a switch, reload
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

The release does not own `~/bin/python` or `~/bin/python3`; standalone Python
is private to its tool payload. kubectl and Helm are public release commands.
Cluster access still needs the appropriate network, kubeconfig, credentials
and any external authentication executables. Krew plugins and optional k9s
helpers are not automatically bundled.

### Selecting a bundled Kubernetes client

The first kubectl or Helm record in `versions.env` is the default. The builder
includes every record for those two tools; other tools use only their default.
Launchers resolve one physical release and run its client without using asdf,
searching `.tool-versions`, downloading tools or detecting the cluster version.

```bash
kubectl version --client
helm version --short

# Select an exact version for one command:
KUBECTL_VERSION=1.34.12 kubectl get nodes
HELM_VERSION=3.22.0 helm list

# Select versions for this shell and commands started from it:
export KUBECTL_VERSION=1.34.12 HELM_VERSION=3.22.0
kubectl get pods
helm list

# Return to defaults from the active release:
unset KUBECTL_VERSION HELM_VERSION
```

Unset or empty variables select the default. An invalid version or a version
not in the active release fails clearly, without falling back to another tool
provider. Explicit binaries such as `current/bin/kubectl-1.34.12` also work;
only the two canonical client launchers are projected into `~/bin`.
`release.env` records ordered `KUBECTL_VERSIONS` and `HELM_VERSIONS` lists.
Health verifies every version and the default independently of the caller's
selection, reads an isolated kubeconfig and renders a local chart offline.

Client selection is inherited by subprocesses that invoke `kubectl` or `helm`
through these launchers. It does not change Kubernetes/Helm libraries embedded
inside other programs. kubectl must be within one minor version of the cluster
API server, as described in the upstream version-skew policy.

Offline Bash does not add asdf shims and removes inherited shim paths from
`PATH`, without modifying asdf's files or settings. Connected Bash continues
to use asdf. Avoid overlapping providers for the same public commands in one
HOME; there is no automatic fallback between them.

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

The historical approximately 460 MiB archive is the whole offline release, not the
standalone Python archive. Archive sizes remain within the original 435-475
MiB estimate. Allocated retained sizes, unlike the earlier apparent-only
figures, are within the original 1.65-1.90 GiB estimate per release. These
measurements predate bundled kubectl and Helm; refresh them for the new payload.

The [Nvim2 offline notes](nvim2/.config/nvim2/offline-releases.md) describe the
editor-specific runtime, health checks and state behavior. `TOOL_UPDATES.md`
describes how a new source revision becomes a separately qualified immutable
release.

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
the physical release. TPM reads plugin declarations from
`${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf` when it exists, otherwise
from `~/.tmux.conf`, even if tmux starts with `-f FILE`. Keep the connected
config in the default location, as in the setup above. For a custom
`TMUX_PLUGIN_MANAGER_PATH`, use an absolute path without whitespace.

On a connected machine, reconcile the managed checkouts with:

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

install_tmux_plugin tpm "$TPM_REPO" \
  "$TPM_COMMIT"
install_tmux_plugin tmux-sensible \
  "$TMUX_SENSIBLE_REPO" \
  "$TMUX_SENSIBLE_COMMIT"
install_tmux_plugin tmux-resurrect \
  "$TMUX_RESURRECT_REPO" \
  "$TMUX_RESURRECT_COMMIT"
install_tmux_plugin tmux-continuum \
  "$TMUX_CONTINUUM_REPO" \
  "$TMUX_CONTINUUM_COMMIT"
```

This resets only the four managed plugin checkouts. Session data under
`~/.tmux/resurrect` remains intact.

Krew remains separate from `setup-tools`. Read its first release record,
download and verify `krew-linux_amd64.tar.gz`, extract `krew-linux_amd64`, then
install the manager:

```bash
set -euo pipefail
source scripts/setup-lib
source versions.env
validate_tool_config
select_default_release TOOL_RELEASES krew
archive=$(mktemp)
work=$(mktemp -d)
trap 'rm -f "$archive"; rm -rf "$work"' EXIT
download_file "$RELEASE_URL" "$archive"
verify_sha256 "$archive" "$RELEASE_SHA256"
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
