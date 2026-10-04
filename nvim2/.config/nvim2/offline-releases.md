# Nvim2 in complete offline releases

The authoritative multi-application build, prerequisite, installation,
ownership, rollback and uninstall procedure is in
[SETUP.md](../../../SETUP.md#complete-offline-release). This page documents the
Neovim-specific parts of that release.

## Editor payload and process identity

Each `dotfiles-COMMIT12-PLATFORM.tar.gz` artifact contains the full official
Neovim tree, the matching `nvim2` configuration, exact `vim.pack` Git
checkouts, Treesitter parsers and queries, and the complete pinned Mason tool
inventory. The dotfiles snapshot, plugin lock and generated Mason receipts all
come from the same source commit recorded in `release.env`.

The connected builder starts from empty Neovim data and runs
`Nvim2ToolsInstallSync` and the tool-enabled test suite. It removes the Mason
venvs for ansible-lint and yamllint before packaging. Their exact generated
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

The release `nvim` launcher resolves its physical release root once. For the
`nvim2` app it sets physical `XDG_CONFIG_HOME` and `XDG_DATA_HOME` plus a
private tool path, while leaving `XDG_STATE_HOME` under user control. An
explicit different `NVIM_APPNAME` is passed through without those overrides.
The launcher saves the caller's XDG and zoxide settings before the overrides;
terminal Bash restores them so user data stays outside the immutable release.
Therefore a Nvim process started from release A keeps configuration, plugins
and tools from A after `current` changes to B. A new process uses B.

Before applying those overrides, the launcher records whether the user's
`XDG_CONFIG_HOME`, `XDG_DATA_HOME` and `_ZO_DATA_DIR` were set and preserves
their exact values. It also sets zoxide's data directory from the original user
data home for direct jobs. A Bash terminal sourced inside Nvim restores the
original environment before initializing zoxide and the other integrations.
The markers survive nested Nvim launches without replacing the first user
values and are consumed only by the release Bash startup.

## Mutable data

The immutable payload never owns ShaDa, undo files, project marks, Mini Visits
or Telescope history. They use `${XDG_STATE_HOME:-$HOME/.local/state}/nvim2`.
On first activation, the manager copies legacy `mini-visits-index`,
`telescope_history` and `telescope_history.sqlite3` from the old data path only
when the destination does not exist. It preserves the source and never replaces
newer state.

Cache and logs also stay outside the payload. In particular,
lua-language-server writes its log below the Nvim2 state directory. Health uses
a disposable HOME, state and cache, so it does not modify the operator's
history, kubeconfig or editor data.

The offline tmux launcher records its physical config in `@dotfiles-config`.
The connected config records its own loaded path. In both cases `prefix` +
`Shift-R` invokes `source-file -F '#{@dotfiles-config}'`. An existing server A
therefore reloads A after `current` selects B; a newly started server uses B.
An explicit `tmux -f FILE` remains authoritative.
Connected TPM still reads plugin declarations from the default config location,
not `FILE`; see [TPM and Krew](../../../SETUP.md#tpm-and-krew).

## Offline health

`dotfiles-release health [ID]` verifies the local content record, file modes,
symlink targets, source metadata, Python isolation and all runtime versions.
The full mode then runs functional rg, fzf, zoxide, Task, Terraform and tfvars
operations, an embedded-library `helm-ls` lint without Helm, isolated
kubectx/kubens and k9s checks, a private tmux socket with all three plugins,
and a real interactive Bash reload. Finally it executes:

```bash
NVIM2_CHECK_TOOLS=1 NVIM2_BENCHMARK_RUNS=3 \
  bash "$PHYSICAL_RELEASE/config/nvim2/tests/check.sh"
```

The Nvim2 suite covers plugin HEAD and cleanliness, Mason receipts and probes,
Treesitter parsers, feature behavior, LSP, diagnostics, formatting and linting.
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
`dotfiles-COMMIT12` release, verifies any existing asset identity, and builds
only missing platform assets. It never creates a tag or release. A qualified
asset is uploaded only after offline install and full health have passed.

Expected assets are:

```text
dotfiles-COMMIT12-debian-13-x86_64.tar.gz
dotfiles-COMMIT12-ubuntu-24.04-x86_64.tar.gz
dotfiles-COMMIT12-ubuntu-26.04-x86_64.tar.gz
dotfiles-COMMIT12-amzn-2023-x86_64.tar.gz
```

For a plugin or configuration change, edit the source checkout, regenerate
`nvim-pack-lock.json` only through `vim.pack`, run repository validation, and
build a new complete release. Never edit the installed snapshot or use it as a
Git working tree. Keep A and B until their health, representative editing,
rollback and process-pinning checks have passed, then remove an inactive ID as
described in `SETUP.md`.
