# Nvim2 in complete offline releases

The authoritative multi-application build, prerequisite, installation,
ownership, rollback and uninstall procedure is in
[setup.md](../../../maintenance/setup.md#complete-offline-release).
This page documents the Neovim-specific parts of that release.

## Editor payload and process identity

Each `dotfiles-COMMIT-PLATFORM.tar.gz` artifact contains the full official
Neovim tree, the matching `nvim2` configuration, exact `vim.pack` Git
checkouts, Treesitter parsers and queries, and the complete pinned Mason tool
inventory. The dotfiles snapshot, plugin lock and generated Mason receipts all
come from the same source commit recorded in `release.env`.

The connected builder starts from empty Neovim data and runs
`Nvim2ToolsInstallSync` and the tool-enabled test suite. It removes the Mason
venvs for ansible-lint, yamllint and debugpy before packaging. Their exact generated
inputs and locks are maintained in the source profile at
`nvim2/.config/nvim2/python-locks/`; the builder copies them into the unchanged
payload path `python-locks/`, alongside the downloaded wheels. The target
installer uses the bundled standalone Python to recreate ordinary isolated
venvs at their final retained paths with `--no-index`, `--require-hashes` and
`--only-binary=:all:`. It never moves a completed venv and does not use a host
Python or site-packages.

The generated `python-locks/inventory.tsv` contains just the Python package
name and version, separated by a tab. It is build/install data, not a file
automatically imported by Nvim.

Python DAP uses the bundled `debugpy` adapter venv and four locked plugins:
`nvim-dap`, `nvim-dap-python`, `nvim-dap-ui` and `nvim-nio`. Both debugpy
entry points are portable launchers that resolve their physical Mason package
and use its final venv without builder paths, user site-packages or bytecode
writes into the release. Neovim retains that physical adapter path even when
another release becomes `current`. The program uses its own selected Python,
preferring an explicit override, active environment or nearest project venv;
only the no-venv offline fallback uses `release/bin/python`.
Project dependencies and application-specific Python versions are not bundled.
There is no TypeScript/Node or browser debug adapter.

Go uses the full official SDK plus Mason's pinned gopls, goimports,
golangci-lint and Delve. The connected builder performs the normal Mason Go
builds with CGO disabled, and the target runs their packaged binaries without
installing or compiling tools. `nvim-dap-go` uses the shared DAP/UI plugins.
Go/manifest parsers and queries are included. Project modules, alternate SDKs
and CGO C libraries are not part of the artifact.

The release `nvim` launcher resolves its physical release root once. For the
`nvim2` app it sets physical `XDG_CONFIG_HOME` and `XDG_DATA_HOME` plus a
private tool path, while leaving `XDG_STATE_HOME` under user control. An
explicit different `NVIM_APPNAME` is passed through without those overrides.
The launcher saves the caller's XDG, zoxide and Go SDK settings before the overrides;
terminal Bash restores them so user data stays outside the immutable release.
Therefore a Nvim process started from release A keeps configuration, plugins
and tools from A after `current` changes to B. A new process uses B.

The physical release tool path includes all bundled kubectl and Helm versions.
Jobs that invoke their canonical commands inherit `KUBECTL_VERSION` and
`HELM_VERSION`. No asdf shims are needed; embedded libraries in programs such
as helm-ls are independent of this client selection. Terminal Bash returns to
the public commands from `current`, as it does for other release tools.

Before applying those overrides, the launcher records whether the user's
`XDG_CONFIG_HOME`, `XDG_DATA_HOME` and `_ZO_DATA_DIR` were set and preserves
their exact values. It also sets zoxide's data directory from the original user
data home for direct jobs. A Bash terminal sourced inside Nvim restores the
original environment before initializing zoxide and the other integrations.
The markers survive nested Nvim launches without replacing the first user
values and are consumed only by the release Bash startup.

For Go-bearing releases, the launcher clears an inherited `GOROOT` and selects
`GOTOOLCHAIN=local`. Go and the Go editor tools use that physical release's SDK
and cannot auto-download a different version. Bash terminals restore the
original Go environment together with the XDG values. The newer manager also
supports original and fd-only retained releases that have no Go metadata.

## Mutable data

The immutable payload never owns ShaDa, undo files, project marks or
Telescope history. They use `${XDG_STATE_HOME:-$HOME/.local/state}/nvim2`.
On first activation, the manager copies legacy `telescope_history` and
`telescope_history.sqlite3` from the old data path only when the destination
does not exist. It preserves the source and never replaces newer state.

Cache and logs also stay outside the payload. In particular,
lua-language-server writes its log below the Nvim2 state directory. Health uses
a disposable HOME, state and cache, so it does not modify the operator's
history, kubeconfig or editor data.

Go's build/module caches use the user's normal writable locations. Go settings
and local telemetry, plus Delve's configuration, use the caller's original
`XDG_CONFIG_HOME` (or `~/.config`), not the editor's release configuration.
Only child-tool environments are changed; Neovim keeps its pinned config path.

eslint_d normally stores its daemon state beside the resolved ESLint package.
The offline launcher uses ordinary ESLint CLI for the immutable bundled
fallback, preserving its diagnostics without daemon files. Project-installed
ESLint keeps the native eslint_d behavior and environment settings.

The offline tmux launcher records its physical config in `@dotfiles-config`.
The connected config records its own loaded path. In both cases `prefix` +
`Shift-R` invokes `source-file -F '#{@dotfiles-config}'`. An existing server A
therefore reloads A after `current` selects B; a newly started server uses B.
An explicit `tmux -f FILE` remains authoritative.
Connected TPM still reads plugin declarations from the default config location,
not `FILE`; see [TPM and Krew](../../../maintenance/setup.md#tpm-and-krew).

## Offline health

Normal `install` checks the candidate before activation, including the full
Nvim2 suite. `install --skip-tests ARCHIVE` skips the extended functional suites
for that invocation while preserving core integrity/runtime checks and Python
venv creation. Use it for an already qualified package when the host cannot
run the functional tests. A subsequent `health` still runs the complete suite.

`dotfiles-release health [ID]` verifies the local content record, file modes,
symlink targets, source metadata, Python isolation and all runtime versions.
It verifies the installed content again after functional checks, so tool writes
into the payload fail the same health invocation.
New releases also bundle kind, uv/uvx, actionlint, ShellCheck, gh, htop,
kubeconform, Kyverno and Trivy. Yamllint is exposed from its locked Python
environment. Health checks their versions and
creates a disposable uv venv using the bundled Python with downloads disabled.
It does not create a cluster, pull images or install project dependencies.
Docker and container images remain separate prerequisites for kind.

The full mode then runs functional rg, fzf, zoxide, Task, Terraform and tfvars
operations, an embedded-library `helm-ls` lint without Helm, isolated
kubectx/kubens and k9s checks, a private tmux socket with all three plugins,
and a real interactive Bash reload. Finally it executes:

```bash
NVIM2_CHECK_TOOLS=1 NVIM2_BENCHMARK_RUNS=3 \
  bash "$PHYSICAL_RELEASE/config/nvim2/tests/check.sh"
```

The Nvim2 suite covers plugin HEAD and cleanliness, Mason receipts and probes,
Treesitter parsers, feature behavior, LSP, diagnostics, formatting and linting,
plus real Python breakpoint/step, venv, module/unittest, exception, terminate,
Neovim-exit and loopback attach/disconnect sessions.
Go checks compile/run/test a multi-file package and an offline vendored module,
exercise gopls navigation/hover/completion, goimports and configured async
golangci-lint, then run real Delve package and cursor-test sessions, goroutines,
locals, stepping and adapter/debuggee cleanup.
Terraform and tfvars continue to use `terraform fmt`. The local Helm chart test
uses helm-ls without a Helm executable. No plugin, parser, language server or
formatter is installed or updated by health. The release launcher uses the
bundled Mason registry snapshot and disables registry refresh, so startup and
health do not make network requests. The manager also passes the candidate's
physical release root to the first health run, before `installed.sha256`
exists, so that initial verification uses the same offline behavior.

For qualification evidence, preserve the unfiltered manager output and the
files produced by the normal Nvim checks, including messages, Mason, Conform
and LSP reports. An optional clipboard-provider warning in a headless
container does not affect editing, while an error in a required plugin, tool,
parser or server is a release failure.

## Platform qualification and workflow

The supported Linux x86-64 platforms are Debian 13, Ubuntu 24.04, Ubuntu
26.04 and Amazon Linux 2023. Standalone Python wheels, tmux dynamic libraries
and the complete Neovim profile are qualified separately in each pinned image.
The final runtime check uses a fresh prepared container, a read-only artifact,
an ordinary user and `--network none`.

`.github/workflows/dotfiles-release.yml` accepts an existing
`dotfiles-COMMIT` release and uses `scripts/dotfiles-release-ci` for planning,
qualification and publication. The workflow tooling comes from the commit
containing the workflow; the separate read-only build checkout is the resolved
release commit, so dispatching an older release does not require newer CI
scripts in that release.

Tag prefixes accept 7-40 lowercase hexadecimal characters; archive names and
retained release IDs use the first 12 characters of the full commit SHA.

Existing archives are checked with the trusted checkout's
`dotfiles-release inspect PLATFORM ARCHIVE COMMIT`: archive paths and links,
complete metadata, expected platform and full commit ID, and internal checksums.
Only missing archives are built. Each archive is published together with its
`.tar.gz.sha256` sidecar. The release also includes a standalone
`dotfiles-release` script, extracted from the qualified Debian archive with its
embedded tool-probe configuration. Download it with the matching platform
archive and checksum; installation needs no Git checkout.
Only the Debian job publishes this shared script. A retry verifies existing
assets and supplies a missing checksum or manager without rebuilding or
overwriting the archive. An existing manager must match the one in the archive;
a mismatched manager or checksum fails rather than being replaced. The workflow never creates
a tag or release. A new archive is uploaded only after offline install and full
health have passed. Qualification logs and metadata are retained even if a
build, verification or upload fails; containers use `--init` to reap debugger
processes and are removed on exit.

Expected assets are:

```text
dotfiles-release
dotfiles-COMMIT-debian-13-x86_64.tar.gz
dotfiles-COMMIT-ubuntu-24.04-x86_64.tar.gz
dotfiles-COMMIT-ubuntu-26.04-x86_64.tar.gz
dotfiles-COMMIT-amzn-2023-x86_64.tar.gz
```

For a plugin or configuration change, edit the source checkout, regenerate
`nvim-pack-lock.json` only through `vim.pack`, run repository validation, and
build a new complete release. Never edit the installed snapshot or use it as a
Git working tree. Keep A and B until their health, representative editing,
rollback and process-pinning checks have passed, then remove an inactive ID as
described in `maintenance/setup.md`.
