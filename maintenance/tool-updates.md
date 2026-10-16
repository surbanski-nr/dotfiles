# Tool updates and rollback notes

Use this runbook to test a new version before changing the normal setup. Every
candidate needs an exact version, a SHA-256 digest from the upstream release,
and the same checks used for a normal installation. Keep the current and the
candidate installations until rollback has been tested.

Run the commands below from the repository root.

## Disposable candidate

Start from an independent clone. The build scripts require a real `.git`
directory. A clone contains committed files only. If the candidate depends on
local changes, copy them deliberately and inspect the resulting diff:

```bash
candidate_root=$(mktemp -d "$HOME/dotfiles-candidate.XXXXXX")
git clone --local --no-hardlinks "$PWD" "$candidate_root/current"
git diff --binary HEAD -- . ':!.cache' >"$candidate_root/working.patch"
if [[ -s $candidate_root/working.patch ]]; then
  git -C "$candidate_root/current" apply "$candidate_root/working.patch"
fi
git ls-files --others --exclude-standard -z |
  tar --null --files-from=- -cf - |
  tar -C "$candidate_root/current" -xf -
git -C "$candidate_root/current" status --short

cp -a "$candidate_root/current" "$candidate_root/candidate"
```

Edit only the intended records in `candidate/tools.env` or builder images in
`candidate/release.env`. `TOOL_RELEASES` stores ordered
`version|full_URL|SHA256` records. The first record is the
default and cannot fall back if its artifact is absent. Actionlint, ShellCheck
and Task use `TOOL_RELEASES` for setup and offline releases. Repository
validation and GitHub Actions use independent `VALIDATION_RELEASES` in
`validation.env`. Yamllint's validation pin is independent of its editor
and offline-package Python locks.
`ASDF_PLUGINS` owns plugin repository and commit pins, while runtime versions
still come from `TOOL_RELEASES`.
For a tmux plugin bump, change its `*_COMMIT` in `tools.env`; change the
adjacent `*_REPO` only when deliberately moving to a different repository.

For a normal dependency bump, edit only its first record in `tools.env`. Run
the focused setup in the disposable candidate, then `task validate` and the
affected platform build and offline checks. To go back, restore the earlier
record as the first record and rerun the same checks. Do not edit generated
Python locks for an unrelated tool bump.

For a repository validation tool bump, edit its record in `validation.env`
and run `task validate`. For yamllint, edit `YAMLLINT_VERSION` in that file.

Htop and tmux records point to official source archives. Both connected setup
and offline release builds compile them through the shared source-build helper,
so test both paths when changing either record.

For a daily tool, install the current selection first, record its version and
canonical link, then run the candidate from the other read-only checkout. This
tested example uses Debian 13 and an immutable image digest. Replace `TOOL` and
the version check for another daily tool:

```bash
image='debian@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a'
tool=k9s

docker run --rm \
  --tmpfs /home/candidate:exec,uid=1000,gid=1000 \
  --mount "type=bind,src=$candidate_root/current,dst=/src-current,readonly" \
  --mount "type=bind,src=$candidate_root/candidate,dst=/src-candidate,readonly" \
  "$image" sh -euxc '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends ca-certificates curl
    useradd --uid 1000 --home-dir /home/candidate candidate
    chown candidate:candidate /home/candidate
    su candidate -s /bin/bash -c '\''set -euo pipefail
      HOME=/home/candidate /src-current/setup-tools '"$tool"'
      readlink "$HOME/bin/'"$tool"'" >"$HOME/baseline-link"
      "$HOME/bin/'"$tool"'" version --short
      HOME=/home/candidate /src-candidate/setup-tools '"$tool"'
      "$HOME/bin/'"$tool"'" version --short
      test -x "$HOME/bin/$(cat "$HOME/baseline-link")"'\''
  '
```

The checkout mounts are read-only and the candidate home is a disposable
`tmpfs`. Never mount the normal home, asdf data or working checkout writable.
Delete a rejected candidate with `rm -rf -- "$candidate_root"`; it cannot have
changed the normal selection.

For an offline candidate, build and verify a complete platform release using
[setup.md](setup.md#complete-offline-release). Do not assemble or import
individual tool archives with `setup-tools`; that script is connected-only.

After the disposable trial, run the setup qualification on Debian 13, Ubuntu
24.04, Ubuntu 26.04 and Amazon Linux 2023. A successful container trial alone
does not qualify a new selection.

## Daily-tool rollback

Versioned installations and their state are retained under `~/bin` and
`~/.local/state/dotfiles/setup-tools`. Inspect them before switching:

```bash
ls -l "$HOME/bin/k9s"*
"$HOME/bin/k9s-0.50.18" version --short
```

For a persistent rollback, put the earlier complete
`version|full_URL|SHA256` record first for that tool in `TOOL_RELEASES`, then
run this command from that reviewed revision:

```bash
./setup-tools k9s
```

If the retained installation is intact, the script reuses it without a new
download. If it is absent, the script downloads the pinned release again.
The same procedure applies to `gh`, `oh-my-posh`, `rg`, Task, actionlint,
ShellCheck and the complete `nvim-VERSION` executable tree. Their records
also supply offline builds. The private validation bootstrap keeps its own
selection in `validation.env`.
Mason ShellCheck keeps its own editor pin.

A temporary switch may update only an existing managed relative link. Check
both the current target and requested executable first:

```bash
cd "$HOME/bin"
case $(readlink k9s) in k9s-*) ;; *) exit 1 ;; esac
test -x k9s-0.50.18
ln -s k9s-0.50.18 .k9s.rollback
mv -T .k9s.rollback k9s
hash -r
type -a k9s
k9s version --short
```

The next `setup-tools k9s` selects the first catalog record again. Keep the
older complete record in `tools.env` for a persistent rollback. Treat `uv`
with `uvx`, `kubectx` with `kubens`, and the complete Go SDK with `gofmt`, as
paired selections. Do not switch only one of the Go SDK links.

## Isolated k9s and MC skin previews

Run these Bash commands from the root of a dotfiles clone. They copy the
candidate configuration rather than stowing it or pointing a writable app
directly at the checkout. Only the child processes receive the temporary
environment; normal host settings and the shell's current directory are not
changed.

Prepare a private preview directory:

```bash
preview_checkout=$(pwd -P)
preview_root=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-skin-preview.XXXXXX")
preview_kind_cluster=
mkdir -p "$preview_root/.config/mc" "$preview_root/.cache" \
  "$preview_root/.local/share/mc" "$preview_root/.local/state"
cp -R "$preview_checkout/k9s/.config/k9s" "$preview_root/.config/"
cp "$preview_checkout/mc/.config/mc/ini" "$preview_root/.config/mc/"
cp -R "$preview_checkout/mc/.local/share/mc/skins" "$preview_root/.local/share/mc/"
printf 'Preview directory: %s\n' "$preview_root"
```

### k9s with disposable workloads

Choose one cluster preparation below, then use the shared fixture and k9s
commands. Both routes keep credentials in the private preview directory.

#### New local cluster with kind

If you do not have a disposable cluster, use a single-node
[kind](https://kind.sigs.k8s.io/docs/user/quick-start/) cluster inside Docker.
It needs no browser, GPU or extra VM. Have `kubectl` and a running Docker
Engine and kind available first; `docker info` must succeed for the intended user.
When Docker is absent, normal `./setup-system` installs and starts it and adds
the invoking user to its group; log out and back in after running it. See the
[Docker setup notes](setup.md#docker). Docker daemon access is root-equivalent;
the preview commands themselves do not change group membership or install a
system service.

Budget roughly two CPUs, 2 GiB of available memory and a few GiB of disk space.
The kind executable is about 10 MB; the pinned node image is about
1.3 GB unpacked. The first start downloads the image and may take a few minutes.
`./setup-tools kind` and the offline payload include kind. Docker is provided
only by normal `setup-system`; node and workload images are not bundled.

Install the catalog-selected kind and create a uniquely named cluster. The
explicit kubeconfig is important during both creation and cleanup:
kind must not merge this context into the host's kubeconfig.

```bash
./setup-tools kind
kind version

preview_kind_cluster="dotfiles-k9s-preview-$(date +%s)-$$"
env KIND_EXPERIMENTAL_PROVIDER=docker \
  timeout --signal=TERM --kill-after=10s 300s \
  kind create cluster --name "$preview_kind_cluster" \
  --image kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed \
  --kubeconfig "$preview_root/kubeconfig" --wait 120s &&
  preview_context="kind-$preview_kind_cluster"
```

Continue only after cluster creation succeeds. On failure, use the kind
cleanup command below before deleting the preview directory.
`KIND_EXPERIMENTAL_PROVIDER=docker` explicitly chooses Docker instead of kind's
automatic Docker/Podman/nerdctl detection. It is redundant with Docker as the
only runtime; here it makes creation and cleanup use the same provider without
exporting a global setting. Keep the kind
version and its documented compatible node-image digest together when updating.

#### Existing disposable cluster

Use only a disposable cluster where you are allowed to create and delete a
namespace. Do not use a production context. Set its explicit context below;
the commands never change the original kubeconfig's current context.
Flattening a private, single-context copy also preserves relative certificate
paths and works when `KUBECONFIG` names multiple files. This copy contains
credentials; keep it private and remove it after the preview.

```bash
preview_context='REPLACE-WITH-DISPOSABLE-CONTEXT'
kubectl --context "$preview_context" config view --minify --flatten --raw \
  >"$preview_root/kubeconfig"
```

#### Deploy the fixture

```bash
preview_kubectl() {
  command kubectl --kubeconfig "$preview_root/kubeconfig" \
    --cache-dir "$preview_root/.cache/kube" \
    --context "$preview_context" --namespace dotfiles-k9s-preview "$@"
}

preview_kubectl create namespace dotfiles-k9s-preview &&
  preview_kubectl apply -f "$preview_checkout/tests/k9s-preview.yaml" &&
  preview_kubectl rollout status deployment/preview-logger --timeout=90s
```

Namespace creation must succeed. If it already exists, stop and inspect it;
do not reuse or delete someone else's namespace. The fixture contains a
logging Deployment, a ConfigMap and Secret with deliberately fake values, and
a CronJob scheduled every minute. Each Job stays running for ten seconds,
then randomly exits with 0 or 1. Retries are disabled; five successful and five
failed scheduled Jobs are retained so their different states remain visible.
Several runs may be needed to see both outcomes. No Service, persistent volume,
privileged container or Kubernetes API access from a Pod is required.

After successful deployment, optionally start a Job immediately rather than
waiting for the next minute:

```bash
preview_kubectl create job preview-now --from=cronjob/preview-random
```

The pinned BusyBox image must be available to the cluster. In a disconnected
cluster, preload it using that cluster's image import mechanism. Starting kind
without network access additionally requires Docker and the pinned node image
to be prepared in advance. The dotfiles offline archive includes kind, not
Docker or container images. This fixture is opt-in; setup and offline-release
installation do not deploy it. A metrics-server is not required for skin
previews; without one, CPU and memory columns show unavailable values.

Launch the copied skin and config:

```bash
env XDG_CONFIG_HOME="$preview_root/.config" \
  XDG_DATA_HOME="$preview_root/.local/share" \
  XDG_CACHE_HOME="$preview_root/.cache" \
  XDG_STATE_HOME="$preview_root/.local/state" \
  K9S_CONFIG_DIR="$preview_root/.config/k9s" \
  K9S_LOGS_DIR="$preview_root/.local/state/k9s" \
  KUBECACHEDIR="$preview_root/.cache/kube" \
  k9s --kubeconfig "$preview_root/kubeconfig" --context "$preview_context" \
  --namespace dotfiles-k9s-preview --readonly
```

Use `:pods`, `:deployments`, `:jobs`, `:cronjobs`, `:configmaps`,
`:secrets` and `:events`. In Pods, press `l` for logs; use `y` for YAML,
`d` for describe and `?` for the available keys in each view. Inspect running,
completed and failed rows, selected rows, headers, dialogs, logs and YAML.
Read-only mode is a UI guard, not an RBAC or filesystem sandbox.

Edit the copied `$preview_root/.config/k9s/skins/surb.yaml` to experiment, or
edit the clone and copy the changed skin over again. To try another bundled
skin, change `k9s.ui.skin` in the copied `config.yaml`. Restart k9s with the
same command after each change; this does not depend on live reload being
enabled. Config, context history, dumps and logs remain under the preview root.
The Kubernetes discovery cache is also isolated; XDG variables alone do not
redirect its default `~/.kube/cache` location.

### Midnight Commander

MC stores its skin and history under the data directory, not just its config
directory. `MC_PROFILE_ROOT` explicitly isolates all three MC directories;
`--skin` selects the copied skin even if the host has an `MC_SKIN` override.
`--nosubshell` avoids sourcing the host's Bash startup files. Run the executable
through `env` so shell aliases/functions are not used.

Prepare a scratch file list so preview operations cannot accidentally change
files in the checkout:

```bash
mkdir -p "$preview_root/files/directory"
touch "$preview_root/files/regular.txt" "$preview_root/files/source.py"
cp "$preview_checkout/tests/fixtures/bash/command" "$preview_root/files/executable"
chmod +x "$preview_root/files/executable"
ln -s regular.txt "$preview_root/files/symlink"
ln -s missing "$preview_root/files/broken-symlink"

env MC_PROFILE_ROOT="$preview_root" \
  XDG_CONFIG_HOME="$preview_root/.config" \
  XDG_DATA_HOME="$preview_root/.local/share" \
  XDG_CACHE_HOME="$preview_root/.cache" \
  XDG_STATE_HOME="$preview_root/.local/state" \
  mc --nosubshell --skin="$preview_root/.local/share/mc/skins/surb.ini" \
  "$preview_root/files" "$preview_root/files"
```

Use Insert to mark files, F9 for menus, F1 for help and F10 to exit.
F5/F6/F8 and confirmation dialogs can be tried only on the scratch files.
Edit the copied `surb.ini`, or copy it again after editing the clone, then
restart MC with the same command. MC remains a file manager with ordinary user
permissions; temporary config is not a filesystem sandbox.

### Cleanup

After closing both applications, delete only the namespace created above and
the private preview directory. The conditional kind command also deletes the
cluster when this preview created it, without changing the host's kubeconfig.
Skip the namespace command for an MC-only trial or a failed cluster creation.

```bash
preview_kubectl delete namespace dotfiles-k9s-preview --wait=true --timeout=90s
if [[ -n ${preview_kind_cluster:-} ]]; then
  env KIND_EXPERIMENTAL_PROVIDER=docker \
    timeout --signal=TERM --kill-after=10s 120s \
    kind delete cluster --name "$preview_kind_cluster" \
    --kubeconfig "$preview_root/kubeconfig"
fi
unset -f preview_kubectl
find "$preview_root" -depth -delete
unset preview_checkout preview_context preview_kind_cluster preview_root
```

## Go SDK and editor tools

The SDK version, official archive and SHA-256 live in `tools.env`. Go is a
direct `setup-tools go` installation, not an asdf runtime. Keep the full
`go-VERSION` tree when testing an upgrade or rollback; it contains the compiler
and standard library, not just two executables.

The gopls, goimports, golangci-lint and Delve pins live in
`nvim2/.config/nvim2/lua/custom/lsp.lua`. Keep their supported Go versions
compatible with the SDK. Mason performs its normal Go package builds in the
connected builder with `CGO_ENABLED=0` and `GOTOOLCHAIN=local`; no separate Go
installer or dependency-building logic is duplicated in shell or Lua. The
upstream golangci-lint binary must also support the selected project Go version.
Go changes do not require regenerating Python locks.

Run `task validate`, rebuild all four complete artifacts, and qualify them
with network access disabled as ordinary users. The tool-enabled Nvim2 suite
checks a real multi-file package, SDK compile/run/test, offline vendoring,
gopls diagnostics/navigation/hover/completion, import formatting, configured
golangci-lint diagnostics and real Delve breakpoint/variables/goroutines/step,
nearest-test and process cleanup. Test rollback to a retained pre-Go release
using the newer manager. Projects requiring another SDK, uncached modules or
CGO libraries need their own separately prepared dependencies.

## Python environments

The prompt deliberately does not display Python virtual environments. Bash
exports `VIRTUAL_ENV_DISABLE_PROMPT=1` so activation scripts do not add their
own prefix, and the Oh My Posh theme performs no venv discovery or rendering.

The Kubernetes segment starts toggled off in each shell session. Run `kp` to
toggle it. This uses Oh My Posh's segment toggle, so the disabled segment is
skipped before it reads or parses kubeconfig files.

The Python-backed Mason packages in a complete release are derived from
`custom.lsp` and the actual Mason receipts. Change a direct version only in
`nvim2/.config/nvim2/lua/custom/lsp.lua`, then regenerate both input and lock
files on a connected machine:

```bash
bash scripts/install-validation-tool task
.cache/validation-tools/bin/task update:python-locks
git diff -- tools.env nvim2/.config/nvim2/lua/custom/lsp.lua \
  nvim2/.config/nvim2/python-locks
```

The generator creates an empty HOME, installs the pinned `PIP_TOOLS_VERSION`
into a venv made with the pinned standalone Python, and reads `M.tools` plus
fresh Mason receipts through Neovim/Lua before resolving against
`https://pypi.org/simple`. It writes
the checked-in `.in` and hashed `.lock` files. For a preinstalled receipt tree,
set `DOTFILES_PYTHON_RECEIPTS` and `NVIM_BIN` explicitly. This is still a
connected operation unless every pip-tools and target dependency is supplied
through an explicitly complete index or `--find-links` workflow. Normal builds
do not resolve dependencies again. The target installs only the locked binary
wheels with `--no-index --require-hashes --only-binary=:all:` and runs
`pip check`; the standalone interpreter alone does not contain ansible-core,
ansible-lint, yamllint or debugpy. The resulting venv executables remain below the
Mason package tree. The release launcher keeps `~/bin` ahead of the private
release paths, followed by the ansible-lint venv, `release/bin` and `mason/bin`.

The Python debugger uses Mason's `debugpy` venv to run its adapter, not the
interpreter selected for the project. After changing the debugpy pin, regenerate
its lock, rebuild complete artifacts, and run the tool-enabled Nvim2 suite on
each platform with networking disabled. That suite starts real launch and
loopback-attach sessions and checks venv selection, locals, stepping, modules,
cursor-selected unittest, exceptions and process cleanup. Browser/TypeScript
adapters are deliberately not part of this profile.

## Offline kubectl and Helm versions

Keep each needed exact client version in `tools.env` as a complete
`version|full_URL|SHA256` record. The builder bundles every kubectl and Helm
record into each release, with the first record as its default. To add a
version, append a verified upstream record; to change the default, move the
required record first. Remove an old record only when it is no longer needed.
Do not change the launcher, regenerate Python locks or edit `release.env`.
Run `task validate`, build the matching platform package and qualify its
offline install and health before deploying.

```bash
KUBECTL_VERSION=1.34.12 kubectl version --client
HELM_VERSION=3.21.0 helm version --short
unset KUBECTL_VERSION HELM_VERSION
```

A missing selection fails rather than downloading or using asdf. Whole-release
rollback selects the previous payload and its defaults; a shell override stays
set until you unset it, so it must also exist in the selected release.

The offline Helm launcher accepts bare versions and one leading `v`. Its
default stays `4.3.0`; `3.21.0` is available for NetReveal.
Connected setup still selects direct links and does not implement
environment-based version selection.

The `helm-schema` artifact record in `tools.env` pins the offline `schema`
addon. Bump that record, then rebuild the ready binary and minimal no-hook
manifest through `build-dotfiles-release`. Keep the plugin's upstream license
when changing its distribution. yq uses the shared raw-artifact path and both
profiles; jq stays an OS runtime prerequisite.
Do not edit generated metadata, installed plugin directories or Python locks.

Qualify new candidates on all four supported platforms with the prepared OS
baseline and network disabled for release installation/health. Check every
Helm version with the bundled plugin, actual schema generation with local
references, yq multi-document processing and jq overlay merges. Health ignores
caller plugin overrides and bin-extras. The tool-enabled editor checks must
opt in explicitly when they qualify save formatting; ordinary sessions start
with format on save disabled. Manual formatting is a one-time action.

Then run NetReveal's `task validate` and the PR `split-generate` path in a
disposable clone with project network inputs allowed. Use the private release
Python to create a suitable project venv, and export project Helm pins for the
entire invocation as shown in
[setup.md](setup.md#helm-schema-plugin-and-project-validation). Keep evidence
of Task/kubeconform compatibility; command availability alone is insufficient.
For a first pre-yq upgrade and any later rollback/return, keep and invoke the
newer standalone manager or reviewed source manager. An older installed
manager does not understand the new metadata fields or yq ownership records.

## Online project runtime rollback

Python uses uv; Node.js, Terraform and Terragrunt remain under asdf. Offline releases do not
install or use asdf. Put the earlier release record first for
the tool in `TOOL_RELEASES`, then reconcile it:

```bash
./setup-tools python
uv python find --show-version
./setup-asdf terraform nodejs terragrunt
asdf current
```

Python setup installs the configured versions without public interpreter links,
then pins the first globally for uv. It does not migrate project version files.
Recreate a project's `.venv` deliberately when changing its interpreter; a
global pin does not replace an existing venv. Python artifacts are managed by
the pinned uv release's own download catalog, while offline builds keep their
explicit URL/SHA-256-pinned standalone runtime.

For asdf, the first version becomes the home default. A project's `.tool-versions` and
an `ASDF_<TOOL>_VERSION` environment override still take precedence. Keep all
required project versions in the list, use the asdf shims, and do not add
same-named launchers in `~/bin`. After changing Node.js or global npm tools,
run `asdf reshim nodejs VERSION` and check both `node --version` and
`npm --version`.

Kubectl and Helm are installed directly by `setup-tools` and included in the
default `TOOLS` profile, not managed by `setup-asdf`.

Outside complete releases, online direct kubectl and Helm installations are
the multi-version case in `setup-tools`. Run a version-qualified executable
temporarily, or put the required version first and rerun setup:

```bash
"$HOME/bin/kubectl-1.27.11" version --client
"$HOME/bin/helm-3.21.0" version --short
./setup-tools kubectl helm
```

To roll back asdf itself or a plugin, restore its executable version, digest
or plugin commit in `tools.env`, run `setup-asdf`, and verify every retained
runtime. For connected tmux, restore the TPM and plugin checkout commits
without deleting tmux-resurrect data. Complete offline releases load sensible,
resurrect and continuum directly from their physical release and do not bundle
TPM. Use Krew's supported manager install or downgrade process so its plugin
inventory is retained.

The current `setup-asdf` can adopt only the exact historical
`~/bin/asdf-VERSION` plus relative `~/bin/asdf` layout for the current pin. It
downloads and verifies the official archive, compares the extracted executable
byte-for-byte, and records ownership only after all requested provider and
plugin preflight checks pass. A conflicting direct launcher, modified binary,
different target or older unverified pin is left untouched and must be resolved
explicitly before retrying.

## Nvim2 candidate and health evidence

Test a plugin change in the disposable checkout and data directories. Use the
documented `vim.pack` update command to regenerate `nvim-pack-lock.json`; never
edit that generated file. A quick copied-data trial does not replace a release
build from empty data.

Run the synchronous tool installation and full check with a timeout. Tool
checks must remain enabled for qualification:

```bash
timeout --signal=TERM --kill-after=30s 1200s \
  env NVIM_APPNAME=nvim2 nvim --headless \
  '+Nvim2ToolsInstallSync' '+qa'
timeout --signal=TERM --kill-after=30s 1200s \
  env NVIM2_CHECK_TOOLS=1 nvim2/.config/nvim2/tests/check.sh
```

Capture unfiltered health and command output after asynchronous checks have
had time to finish:

```bash
evidence_dir=${1:-"$PWD/nvim2-health"}
mkdir -p "$evidence_dir"
timeout --signal=TERM --kill-after=10s 180s \
  env NVIM_APPNAME=nvim2 nvim --headless \
  '+Nvim2Check' '+checkhealth' '+sleep 10' \
  "+silent write! $evidence_dir/checkhealth.txt" \
  "+redir! > $evidence_dir/messages.txt" '+silent messages' '+redir END' \
  '+qa'
timeout --signal=TERM --kill-after=10s 180s \
  env NVIM_APPNAME=nvim2 nvim --headless \
  '+Mason' '+sleep 2' \
  "+silent write! $evidence_dir/mason.txt" '+qa'
timeout --signal=TERM --kill-after=10s 180s \
  env NVIM_APPNAME=nvim2 nvim --headless \
  '+ConformInfo' "+silent write! $evidence_dir/conform.txt" '+qa'
timeout --signal=TERM --kill-after=10s 180s \
  env NVIM_APPNAME=nvim2 nvim --headless \
  '+checkhealth vim.lsp' '+sleep 2' \
  "+silent write! $evidence_dir/lsp.txt" \
  '+qa'
cp "${XDG_STATE_HOME:-$HOME/.local/state}/nvim2/mason.log" \
  "$evidence_dir/mason.log"
```

The commands above capture `:ConformInfo`, `:checkhealth vim.lsp` and custom health output
for review. Review every warning and error. Record optional unavailable host
services instead of hiding their messages. Open representative Python, Lua,
Bash, TypeScript/TSX, Terraform, Ansible, Helm and YAML files and check LSP,
diagnostics, formatting, highlighting, folds and keys. Measure comparable
startup runs before and after the candidate.

Run `task validate`, build and disconnect-test every affected platform release,
then repeat the four-distribution qualification before transferring the
reviewed diff to the normal checkout.

## Complete offline release rollback

Use `dotfiles-release rollback` to select the retained previous unit, including
all tools, configuration, plugins and language support. Existing Neovim and
tmux processes remain pinned to the physical release from which they started.
Follow
[the offline release runbook](../nvim2/.config/nvim2/offline-releases.md) for
checksum verification, activation and exact-ID uninstall. Older artifacts may
use their documented `~/.local/opt` executable roots; retain those roots during
migration.

Do not combine an older editor with arbitrary newer plugin data. Keep the
previous release until editing, health and disconnected runtime checks pass.
Plain `uninstall` restores the baseline without deleting retained payloads.
`uninstall ID` removes only an inactive, integrity-checked release.

For an editor-independent recovery path, use `vi FILE` or `vim FILE`. To bypass
optional Vim configuration and plugins, use `vim -Nu NONE FILE`. For a Git
operation whose normal editor selects Neovim, run it with `GIT_EDITOR=vim`.
