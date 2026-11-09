# Dotfiles setup notes

The supported setup target is Linux x86-64 on Debian 13, Ubuntu 24.04,
Ubuntu 26.04 or Amazon Linux 2023. Run the scripts as the intended ordinary
user. In the connected workflow, run from the repository root; only
`setup-system` uses `sudo`. Release host preparation uses `dotfiles-release setup`,
while payload installation and selection never use `sudo`.

For repository maintenance, see [adding and removing tools](#adding-and-removing-tools)
and [managing OS support and offline publication](#managing-os-support-and-offline-publication).

## Connected machine

Clone the repository, then run:

```bash
cd "$HOME/github.com/surbanski/dotfiles"
./setup-system
./setup-tools
# Optional online project runtimes:
./setup-asdf terraform nodejs terragrunt
./scripts/dotfiles-release set online
# Additional packages outside the managed installation:
./bstow --dry-run -v -t "$HOME" stow \
  mc gnupg codex
./bstow -v -t "$HOME" stow \
  mc gnupg codex

source "$HOME/.bashrc"
hash -r
dotfiles-check
```

Both flows publish managed commands through the same selection:

```text
~/dotfiles-releases/
  current -> online or dotfiles-COMMIT
  online/
    bin/                  command links and optional asdf shims
    tools/                retained versions and complete runtime trees
    dotfiles -> CHECKOUT   editable repository configuration
    state/                installer ownership records
    config/ and share/    editor configuration and data, tmux plugins
    release.env           generated TOOLS selection and version metadata
  dotfiles-COMMIT/         prepared offline package with a frozen checkout
```

Use an absolute `DOTFILES_RELEASE_ROOT` to relocate the whole store. Both
connected installers always write `online`, even while an offline package is
selected. Setup prepares tools; `./scripts/dotfiles-release set online` selects
them and links base Bash, Git, SSH and Vim configuration plus selected tools'
configuration into HOME. The same manager handles offline selection, backups,
recovery and uninstall. Online configuration follows edits and pulls in the Git
checkout; offline configuration stays frozen. Online editor data is retained
when switching away and back.

Activation saves existing files or directories as `<path>.before-dotfiles-release`
and refuses conflicting backups and unsafe parent paths. This includes existing
Bash startup files and SSH configuration. Review the saved originals when
merging local settings. Additional `bstow` packages keep their own ownership and
conflict checks.

`~/bin` contains your executable overrides in both flows. The installers do
not publish tools there. After preparing `online`, use
`dotfiles-release set online`, `dotfiles-release set ID`,
`dotfiles-release health [ID]` and `dotfiles-release uninstall [ID]`.
`dotfiles-check` delegates to the selected installation's health checks.

### Moving from the former connected layout

Stop older installers before using the shared store. Review old `~/bin` links
and payloads: they now take priority as user overrides. Move or remove only the
old managed entries you identify, retaining personal scripts and overrides.
The new installers create fresh ownership records under `online/state`; they
do not adopt old payloads or delete old XDG state.

Older offline packages using `OFFLINE_TOOLS` must be rebuilt. If you need to
remove one, use its original manager before selecting `online`. The current
manager accepts the current metadata layout rather than keeping a permanent
compatibility path.

Interactive Bash shells preserve a working inherited agent, including SSH
forwarding. Otherwise they use the fixed socket of `dotfiles-ssh-agent.service`.
Starting the user service is idempotent, so Bash and tmux panes using this
socket share keys added in any one of them. The managed SSH config selects
`~/.ssh/github` and `~/.ssh/bitbucket`. Enter the passphrase in a terminal with
`ssh-add ~/.ssh/github ~/.ssh/bitbucket`, or on the first SSH connection, which
adds the key automatically. Systemd starts the empty agent and never prompts
for passphrases. Keys remain unlocked only until the agent stops; restarting
the agent or rebooting requires adding them again. User lingering is not
enabled automatically. Activation backs up a pre-existing `~/.ssh/config`;
review it before relying on the managed host settings.

Both deployment flows keep interactive Bash history in `~/.histfile`, outside
the repository and release payloads. Before each prompt, synchronization takes
`~/.histfile.lock` and uses `history -a` to append this shell's new commands.
After a successful save, `history -c` clears only the in-memory list and
`history -r` reloads the shared file. This avoids missed or duplicated entries
when several shells append between prompts, including after archiving. A
failed save leaves commands in memory; an unset or empty `HISTFILE` disables
synchronization. The first prompt accepts a missing history file when there
are no commands to save; the first command creates it. Normal exits append
under the same lock and disable Bash's
implicit exit write. A failed append, or a failed exit lock, also preserves a
private `~/.histfile-unsaved.*` memory snapshot (or a temporary-directory fallback)
and prints its path. Review that copy manually; it is not merged automatically.
Bash can reset its pending-entry counter even after a failed disk write, so
this copy protects commands that a later refresh could otherwise discard.
If both recovery locations fail, refresh keeps the memory list until a copy
can be saved; repeated sourcing does not remove that protection. If storage
still cannot accept a copy at exit, the warning cannot guarantee recovery.
Reloading `.bashrc` preserves unrelated prompt and EXIT hooks without adding
duplicates or changing the exit status. These are hooks from other shell
integrations, such as zoxide and Oh My Posh, or your own `~/.extras` cleanup
commands; they belong to the same shell, not to other users.

No systemd service or timer is used for history. At the first prompt and then
at most once every five minutes per shell, `scripts/bash-history-archive`
checks the shared file under the same lock. At 90000 or more entries it archives
the oldest 80000 into a private `~/.histfile.d/history-*.hist` file and leaves
every remaining entry, including any threshold overshoot. Timestamps and
multiline commands stay together. The archive is fully written and flushed
before atomically replacing the live file. A failed check warns and lets
synchronization continue; an interruption between publication and replacement
can leave duplicate entries in an archive, not lose their only copy. Archives
are retained without an automatic expiry policy and do not appear in Up-arrow
searches. Inspect them with `less ~/.histfile.d/history-*.hist`, or run a manual
check with `bash "$DOTFILES/scripts/bash-history-archive" "$HISTFILE"`.

The per-prompt archive trigger is only a Bash time comparison, not a file count.
Each actual check has a 20-second deadline. Writer locks wait up to two seconds
and archive locks up to five seconds. `HISTSIZE=100000` bounds only memory;
`HISTFILESIZE=-1` prevents Bash's line-based truncation from deleting unarchived
commands. Close or reload every older shell before relying on coordinated
archiving: older writers do not take this lock. Unsaved commands in a forcibly
killed shell cannot be recovered. Do not remove the lock file to bypass a lock.

Commands beginning with a space are omitted, consecutive duplicates are
skipped, and older repetitions are removed from the in-memory list when
recording commands with `HISTCONTROL=ignoreboth:erasedups`. Imported entries are
not filtered, so repeated executions already saved in the shared file can
reappear after a refresh. Synchronization does not deduplicate the file.

`tools.env` owns tool lists, release records, version checks and asdf/tmux
plugin pins. It stores direct releases in `TOOL_RELEASES`. Each tool has ordered
`version|full_URL|SHA256` records, and the first record is the default. A
required default without an artifact is an error, with no fallback to a later
record. Actionlint, ShellCheck and Task are also regular development tools;
their records supply connected setup and offline releases. `dotfiles-check`
checks this development catalog. Repository validation has independent pins
in `validation.env`. Mason ShellCheck remains an independent editor pin.
`ASDF_PLUGINS` and `TMUX_PLUGINS` both map plugin names to `repository|commit`.
Git plugins use commit identity, not an archive version or a separate SHA-256
ownership record.

Yamllint has no prebuilt executable archive. Repository validation installs
the exact `YAMLLINT_VERSION` from `validation.env` with pip in an isolated
venv. Offline releases use the Nvim Python lock and expose that executable
in `release/bin`.

`TOOLS` and `OFFLINE_RELEASE_TOOLS` are the authoritative tool lists, with
one tool per line. Each includes tmux-sensible, tmux-resurrect and tmux-continuum
as separate Git-backed tools, in startup order. The tmux binary remains a
separate source-archive tool. Both include `fd`, installed from its verified official
Linux musl archive rather than an OS package. GNU `find` remains a system
prerequisite for scripts that depend on its semantics.

Both lists must contain at least one tool. An empty list is a configuration
error and stops setup before installation. A single tool is supported, subject
to the explicit offline dependencies below.

Both lists include Mike Farah's yq `4.52.4` as the verified upstream Go
binary, independently of the Python package also named yq.

Both lists also include the full official Go SDK, verified with its
upstream SHA-256. Connected setup keeps it under `online/tools/go-VERSION` and selects
`go` and `gofmt` together with relative links. The SDK includes its compiler,
tools and standard library. No asdf Go plugin or OS Go package is required.

`setup-tools` downloads and installs direct online tools from these exact
official release records. Python runtime management delegates to uv as described
below. It supports only connected installation; offline
deployment uses the complete release described below. Without names, it
installs all of `TOOLS`, including kubectl, Helm and the three tmux plugins.
It announces each tool and version before installation, along with Python and
tmux plugin operations, so long-running steps are visible.
A named `./setup-tools tmux` request installs only the binary; plugin names are
selected independently. Optional online
`setup-asdf` reads runtime versions from the same catalog, but plugin repository
and commit data from `ASDF_PLUGINS`, whose keys are also the supported tool
list and the alphabetical no-argument install order; plugin downloads and
verification remain asdf's responsibility. It selects the first version for
each runtime as the home default. A project `.tool-versions` file continues to
override those defaults.
`setup-asdf` reuses only binaries whose SHA256 matches its installation record.
Existing binaries or links without that record are rejected without being
changed; there is no automatic adoption.

Entry scripts explicitly source the sibling libraries they use and coordinate
their calls. There is no chain of implicit library imports:

- `scripts/setup-lib` supplies common errors, prerequisites, list membership,
  locking and cleanup. `report_error()` returns failure; the caller decides
  whether to return, recover or end the process.
- `scripts/setup-catalog-lib` loads and validates tool catalogs, selects release
  and Git plugin records, and writes tool metadata from those records.
- `scripts/setup-recipes-lib` describes artifact layouts and prepares concrete
  payloads: hashing, extraction, executable checks and source compilation.
  It receives the version, asset name, digest and paths from its caller.
- `scripts/setup-tools-lib` declares shared command, dependency, configuration,
  metadata-field and payload rules, and checks tool inventories.
- `scripts/setup-online-lib` manages the connected store, its lock, directories
  and publication. The caller supplies the checkout and prepared metadata.
- `scripts/setup-system-lib` loads system/platform configuration and owns OS
  detection and package roles.
- `scripts/setup-tmux-lib` installs and verifies tmux Git checkouts using the
  repository and commit supplied by setup-tools or the builder.
- `scripts/dotfiles-release-lib` supplies shared release metadata parsing,
  verification and health checks. The `dotfiles-release` CLI owns activation
  transactions, rollback, uninstall and its process lifecycle.

For kubectl, the entry script selects a catalog record, downloads its URL and
passes its version, asset and SHA-256 to the recipe. Shared tool rules declare
the `kubectl` command and `KUBECTL_VERSIONS` field. The entry script then
publishes the prepared payload and metadata. Node's additional npm archive and
tmux's Git pins are also selected explicitly by their entry scripts.
Libraries can reuse common helpers; catalog validation does not call recipes,
and recipes do not select catalog records.

`load_tool_catalog(PATH)`, `load_system_config(PATH)` and
`load_platform_config(PATH)` read trusted Bash configuration from an explicit
repository or source-snapshot path. Generated package `release.env` is parsed
as strict metadata by `dotfiles-release-lib`; it is never sourced as code.
There is no configuration registry or cache. Sourcing a library only defines
functions; it does not set shell options, initialize installer state, register
traps or load configuration. Entry scripts own those decisions.
Asdf still installs its own executable and delegates plugins/runtimes to asdf.
The standalone manager embeds common runtime checks, without online installers
or artifact recipes.

Edit OS package lists and their expected commands in `system.env`. Common
runtime packages are included in every role; build and setup roles add
their own common and distribution-specific packages. These packages have no
version pins and use the current apt/dnf repository candidates. The same file
lists commands each connected entry point requires before installation.
Package names and command names are separate, since packages such as
`diffutils` provide commands such as `cmp`. Amazon Linux's full GnuPG swap
remains part of the connected installation procedure.

The runtime role is the minimal OS baseline for running a prepared offline
release, including OS-managed jq for JSON schema overlay merges. Normal setup
inherits jq too; it is not a second bundled CLI. The build role adds compilers
and libraries for disposable release builders. The setup role is the normal host setup: download and
verification tools, interactive utilities such as mc, and
headers for remaining asdf runtime builds and native project dependencies, plus
Docker Engine for local containers and release builds. It is
not a second release-builder role; builder-only packages stay out of it.

`TOOL_CHECKS` in `tools.env` maps command names to
`release_metadata_field|version_arguments` for `setup-tools`, shell diagnostics
and release runtime checks. Arguments are whitespace-separated; empty arguments use
`--version`. The metadata field is empty for kubectl and Helm, whose retained
versions are checked through separate lists. Commands such as `node` and `uvx`
have their own entries even when their releases share a tool record. The
builder embeds this map, the shared rules from `scripts/setup-tools-lib` and
checks from `scripts/dotfiles-release-lib` in the standalone manager, alongside
the runtime OS configuration and common setup helpers, so it works outside the
checkout. Edit the repository sources and rebuild; do not edit generated
managers.

Kubectl and Helm are installed directly by `setup-tools`, not `setup-asdf`.
You can select just those tools:

```bash
./setup-tools kubectl helm
"$HOME/dotfiles-releases/online/bin/kubectl-1.27.11" version --client
"$HOME/dotfiles-releases/online/bin/helm-3.21.0" version --short
```

Versioned installations remain in `online/tools`. For each requested tool, setup
installs every catalog version, then points the relative canonical command links
at the first record. `setup-tools: selected NAME VERSION` reports that link
selection. `setup-tools: reuse NAME VERSION` means the recorded installation
passed its integrity check and needs no download or rebuild.

To change the default, move the desired complete record first in
`TOOL_RELEASES[TOOL]` in `tools.env`, then rerun `./setup-tools TOOL`. Running
setup from an older reviewed repository revision can also select a retained
version. For a temporary change, point the link at an already installed version:

```bash
readlink -- "$HOME/dotfiles-releases/online/bin/kubectl"
ln -sfn -- ../tools/bin/kubectl-1.27.11 "$HOME/dotfiles-releases/online/bin/kubectl"
kubectl version --client
```

The next `./setup-tools kubectl` restores the first catalog record. Connected
setup uses ordinary symlinks; `KUBECTL_VERSION` and `HELM_VERSION` affect only
the [offline client launchers](#selecting-a-bundled-kubernetes-client).
Terraform and Terragrunt use optional `setup-asdf` in this connected flow.
Htop and tmux are compiled by `setup-tools` from their checksum-verified
official source archives. Those pinned upstream releases provide source archives
rather than Linux executables; building against the host libraries keeps the
catalog versions independent of apt/dnf package candidates.
The Go SDK is a direct setup tool so the editor and
offline builds use the same reviewed runtime.

### Python through uv

`./setup-tools python` installs the pinned uv/uvx pair and every Python version
listed in `TOOL_RELEASES[python]`. The first record sets uv's global default in
`${XDG_CONFIG_HOME:-$HOME/.config}/uv/.python-version`. uv uses its own
release-frozen download catalog and verifies its prebuilt standalone Python
downloads; the Python archive URL and SHA-256 in `tools.env` continue to supply
the immutable offline build. No Python compilation or asdf plugin is needed.
Normal `./setup-tools` includes this step.

Offline metadata records the standalone build date as `PYTHON_BUILD`, derived
from the default Python archive URL. It has no separate pin in `tools.env`.

Setup never edits project `.tool-versions`, `.python-version` or dependency
files. uv does not read asdf's Python entries. Existing uv project pins and
`requires-python` constraints still take precedence over the global default;
without those project overrides, the catalog's first version is used. Use uv
or activate an ordinary project environment:

```bash
uv venv
source .venv/bin/activate
python --version
```

Setup uses `uv python install --no-bin`, so it does not create extra Python
links or shims and does not replace the OS Python. Outside a venv, use
`uv run --no-project python` for the uv-selected interpreter. Bash still
preserves active venv precedence. Old asdf interpreters, shims and dependent
venvs are not deleted: review them before removing the old provider. Recreate
old project or Mason venvs before deleting an interpreter they still reference.

Neovim's Python debugger and Pyright use the existing project `.venv`; no uv
resolver is added to Neovim. Connected Mason can keep using OS `python3` from
`setup-system` for its isolated tool venvs. Ruff is a standalone executable,
and Pyright runs on Node.js. Offline editor venvs keep using the bundled private
Python and hashed wheels independently of uv or any project.

### Docker

When Docker is absent, both `./setup-system` and `dotfiles-release setup`
install Docker Engine and enable and start its Docker and containerd systemd
services. No extra Docker flag is needed. Debian and Ubuntu use Docker's
[official apt repository](https://docs.docker.com/engine/install/debian/),
including the Compose and Buildx plugins. Amazon Linux 2023 uses the
[distribution's Docker package](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-docker.html)
as recommended by AWS; it does not include those separate plugins. Docker
packages use current repository candidates, like other OS packages.

For a new installation, the script adds the invoking ordinary user to the
`docker` group, preserving existing groups. When invoked through `sudo`, it
uses `SUDO_USER`; a new installation run directly as root without an ordinary
target user is rejected. Membership grants
root-equivalent access to the host. Log out and back in, then verify:

```bash
docker info
docker run --rm hello-world
```

The installer checks the local daemon through its Unix socket without pulling
images. It does not open a TCP listener or modify Docker daemon settings.
An existing Docker command or installed Docker/container runtime package makes
the script skip Docker setup and continue with the other system packages. It
does not change that installation's packages, services or user groups, and it
does not require a working Docker daemon to complete setup. This includes a
conflicting provider such as distribution Docker, Podman compatibility or a
standalone containerd. Configure access to an existing runtime separately.
Without an installed runtime, a legacy `docker.list` or differing
`docker.sources` still stops new Docker installation rather than being
overwritten.
Existing images, containers and volumes are not deleted.

The Debian/Ubuntu installation packages follow Docker's current documentation;
the shared conflict list is the union of their documented incompatible packages.
Amazon Linux's conflict list is a local protection against replacing another
provider, not an upstream Docker instruction.

Full VM installations use systemd by default. Both package roles explicitly ensure
the `systemctl` prerequisite, then start the services; installing the package
does not make a minimal container boot systemd. Use a VM for host setup.
Disposable release builder/runtime images deliberately do not install Docker
or systemd. Docker and container images are not bundled; kind is included as a
CLI tool and needs a separately available container runtime.

### Reruns and recovery

`setup-system` and `dotfiles-release setup` repeat the ordinary package-manager
operation and skip Docker once it is present. OS package operations have a
600-second deadline, signing
key downloads 120 seconds, Docker service startup 180 seconds and the local
daemon check 30 seconds. Timed-out commands are killed after another five seconds.
Host setup announces the package role and platform, names each apt/dnf
operation before starting it and streams command output as it runs. APT setup
runs `apt-get update` followed by `apt-get install` for the configured packages.
Network/DNS/connection failures and timeouts are warnings, not fatal errors.
The script continues independent steps, tries package installation even if
an index refresh failed, and reports missing prerequisites after a network
failure. It does not publish a Docker repository or install Docker when the
signing key could not be downloaded. A warning summary replaces the "ready"
message, and setup exits successfully so other bootstrap steps can continue.
Restore network access and rerun setup before using the prepared release.
On Debian and Ubuntu, an interrupted package transaction can also leave dpkg
needing repair. If a rerun reports "dpkg was interrupted", run
`sudo dpkg --configure -a`, then rerun host setup. This package-manager recovery
is separate from the user-tool publication recovery described below.
Invalid arguments, unsupported hosts, missing commands without prior network
failures, unsafe repository configuration, signing/integrity failures and
other installation errors remain fatal. `dotfiles-release` still rejects
missing system prerequisites and invalid or incomplete packages; warnings do
not bypass its verification or health checks. Release builds remain strict.

For binary tools, `setup-tools` reuses
intact recorded payloads, completes intact pending payloads without downloading,
and reinstalls inactive partial payloads. A failed multi-command selection
attempt restores the prior links; after a killed process, rerunning reconciles
each link to the first configured version. This is not a transaction across
all requested tools: earlier successfully selected tools remain selected.

`setup-asdf` records verified binary ownership before publishing the binary, then
selects it with an atomic replacement of `online/bin/asdf`. That link is the only
selected-version record. Rerunning finishes interrupted publication, verifies
retained binary content, reuses installed runtimes and regenerates shims. It can
restore a missing command link and accepts a manual selection of another intact,
recorded binary before selecting the catalog pin again. Obsolete `asdf-target`
and `pending-selection` files are ignored and left untouched. Partial runtime
builds remain the asdf plugin's responsibility; a broken provider installation
may require provider-specific repair. Home defaults are changed only after all
requested runtime installations succeed.

Both installers and the release manager share one nonblocking process-held
lock on the release root directory itself. This serializes `setup-tools`,
`setup-asdf` and release installation, selection or removal, even for different
tools or a custom store. There is no lock file or separate XDG lock location.
The kernel releases the lock when the last holding descriptor closes, including
after a killed process; a running child may retain an inherited lock until it
exits. Do not rename or replace the store to bypass an active lock.

Modified managed binaries, malformed ownership state, foreign paths and dirty
plugin checkouts fail safely instead of being overwritten. Do not delete state
to bypass those checks. These are process-interruption guarantees, not a promise
of power-loss durability on every filesystem.

System `vi` is explicitly installed in the runtime baseline; normal setup adds
`less`. Operational helpers have their own prerequisites: `checkbackups` needs
`jq`, and `postgres-db-list` needs `psql`. The minimal offline baseline does not
install those optional clients.

### Optional local k9s skin preview

Inside the development VM, [task k9s](tool-updates.md#k9s-tasks-inside-the-development-vm)
creates or reuses a single-node kind cluster with preview workloads and a
private kubeconfig. Existing configuration and skin files are symlinked from
the checkout; generated k9s data stays in a private profile outside it.
Closing k9s leaves the cluster running. `task k9s:clean` removes the cluster and
profile explicitly. Normal `./setup-system` provides Docker; log out and back
in before using it without sudo. `./setup-tools kubectl kind k9s` and offline
releases provide the clients. Cluster creation and image downloads remain opt-in.

## Adding and removing tools

The lists in `tools.env` select tools whose installation is already implemented.
Adding a new name also requires an artifact recipe and verification support.
The steps below use `mytool` as a placeholder for an ordinary standalone CLI.
OS support is managed separately in the [platform instructions](#managing-os-support-and-offline-publication).

An ordinary single executable usually needs changes only in `tools.env` and
the shared artifact recipe in `scripts/setup-recipes-lib`, plus its functional test.
The existing installers and version checks handle it without a new setup
script, Task entry or workflow. The additional steps below cover exceptions
such as runtime trees, plugins and configuration files.

### Selecting or disabling an existing tool

Edit the existing arrays in `tools.env`, keeping one tool per line:

- `TOOLS` selects the default connected installation and required connected
  `dotfiles-check` diagnostics.
- `OFFLINE_RELEASE_TOOLS` selects the next offline archive's executables,
  launchers, plugins and tool-specific configuration.

The lists are independent. Comment a tool in one list to disable only that
flow, or in both to disable both. Keep its release records and implementation
for an easy reversal. Both lists must remain nonempty; a single tool is valid
when its dependencies are satisfied. Dependencies are not automatically
removed with the tool: review the remaining selection and run
`bin/task validate:tools`.

Selection is membership in the corresponding list. An offline archive freezes
`OFFLINE_RELEASE_TOOLS` under the same name in its generated `release.env`.
Online metadata records `TOOLS`. The manager and functional runner use the
selected installation's saved list. Later edits affect the next setup/build.

After commenting a connected entry, run `./setup-tools` without names.
It removes that tool's authenticated command links from `online/bin` while
retaining versioned payloads and ownership records for rollback. Named requests
install only the requested tools and do not prune other commands.
Then run `./scripts/dotfiles-release set online` to reconcile HOME configuration
with the new selection. User overrides in `~/bin` and optional asdf/provider
data are preserved. To remove the whole online installation, use
`dotfiles-release uninstall online`; the editable checkout stays outside it.

For individual disk cleanup, inspect `type -a mytool` and
`ls -la "$HOME/dotfiles-releases/online/bin"`. Remove only inactive, reviewed
payloads under `online/tools` and their matching records under
`online/state/setup-tools`. Keep versions that links or processes still use.
Additional configuration managed separately by `bstow` is removed separately:

```bash
./bstow --dry-run -v -t "$HOME" unstow mytool
./bstow -v -t "$HOME" unstow mytool
hash -r
```

Removing an offline entry affects newly built archives. Build a new package,
then install or select it normally. Selection removes obsolete managed HOME
links and restores saved originals while preserving user data. Existing
archives and retained installations are not rewritten or automatically deleted.

To restore a tool, uncomment its selection and rerun connected setup, or build
and select a new offline archive. When permanently deleting implementation,
first uninstall retained packages that require it, using their original
embedded manager. A newer manager need not keep removed tool rules just to
recognize those packages. Do not delete a release record still used by another
selection or an asdf plugin.

### Adding a standalone tool

1. In [tools.env](../tools.env), add an ordered `TOOL_RELEASES[mytool]`
   record with its exact version, full HTTPS artifact URL and upstream SHA-256.
   Add the name to `TOOLS`, `OFFLINE_RELEASE_TOOLS`, or both.
   Add `TOOL_CHECKS[mytool]='MYTOOL_VERSION|'`; empty arguments mean
   `--version`. Supply different version arguments after the separator when
   needed. Keep the metadata name uppercase and ending in `_VERSION`.
   Connected setup retains every direct version; offline builds normally
   bundle the first. Kubectl and Helm bundle every listed version in both flows.
2. In [scripts/setup-recipes-lib](../scripts/setup-recipes-lib), extend
   `artifact_layout()`. Reuse an existing format where possible: `yq` is raw,
   `zoxide` is a gzip member, `rg` has a nested member and `terraform` is a zip
   member. The recipe declares extraction members, versioned `SPEC_DESTS` and
   public `SPEC_LINKS`. For a standalone executable, follow
   `mytool:mytool-$version`; the shared normalization puts its payload in
   `tools/bin/mytool-VERSION` and makes `bin/mytool` point there.
   Both flows select and download the catalog record in their entry script,
   then call the same
   `prepare_tool_artifact(name, version, asset, sha256, archive, stage)` for
   hashing, extraction, executable checks and any source build, followed by
   `publish_tool_artifact()`.
   A source recipe sets `SPEC_BUILD=true` and extends `compile_tool_source()`
   if it needs different configure flags. Declare build dependencies in the
   setup/build roles in `system.env`. An ordinary CLI needs no branch in
   `setup-tools` or `build-dotfiles-release`.
3. In [scripts/setup-tools-lib](../scripts/setup-tools-lib), review
   `tool_commands()`, `tool_metadata_fields()`, `tool_payload_paths()` and
   `tool_dependencies()`. Their defaults cover a single command matching the
   tool name, a payload under `tools/bin`, one version field and no dependencies.
   Add branches only for additional commands, shared version fields, runtime
   trees or required companions. Additional aliases such as `node`, `npm` and
   `uvx` must not become separately selected tools in `known_tool_names()`.
   Metadata writers in `setup-catalog-lib` and the manager follow these
   declarations; there is no separate metadata allowlist or ordinary-tool
   builder category.
4. Add special integration only when the tool needs it. Map repository
   configuration in `tool_config_package()`; offline packing follows that
   mapping, while online uses the editable checkout. Declare HOME paths in
   `release_projection()` in
   [scripts/dotfiles-release-lib](../scripts/dotfiles-release-lib) and
   `managed_home_links()` in
   [scripts/dotfiles-release](../scripts/dotfiles-release), guarded by selection,
   so the shared manager can activate, remove and restore them in both flows.
   Keep mutable user data outside frozen offline payloads. A plugin, private
   editor dependency or custom launcher may need a focused builder or runtime
   hook. Put downloads and compilation in setup/the builder; offline target
   installation consumes prepared payloads.
5. Add the relevant [tool tests and qualification](#tool-tests-and-qualification)
   below. Usually this means a functional `tests/tools/mytool.sh` suite and
   extending an existing installer scenario, without a new setup script,
   runner, Task entry or workflow. Update this guide when default selection or
   installation behaviour changes; use [tool-updates.md](tool-updates.md) for
   version changes and rollback.

A wrapper such as `scripts/offline-mytool` is needed only when the tool
requires release-specific environment, state paths or runtime selection.
Simple executables use relative symlinks. If a wrapper is necessary, install
it through the builder's `write_launchers()` and extend
`tests/offline_launchers_test.sh`, or the existing focused wrapper test
when it needs its own behaviour. Do not hand-edit the generated
`dotfiles-release`, payload `release.env`, checksums or installed manifests.
`scripts/build-standalone-script` embeds repository sources during a normal
build; no new embedding step is needed for an ordinary tool.

### Tool tests and qualification

Verification has separate jobs:

- `bin/task validate:tools` checks catalogs, selections, dependencies and
  artifact recipes without downloading.
- Connected `setup-tools` verifies staged executable versions and recorded
  payload integrity. Active `dotfiles-check` delegates to `dotfiles-release health`,
  which uses saved selection and `TOOL_CHECKS` in both flows. Before activation,
  its checkout diagnostics read `TOOLS` directly. Ordinary tools need no branch.
- Offline `dotfiles-release verify` validates metadata, exact public commands,
  selected configuration, manifests and safe symlinks without executing tools.
  `install`, `set` and `health` also use `check_runtime()` from
  `scripts/dotfiles-release-lib` for presence, isolated execution and versions.
  These checks normally follow the shared tool rules and `TOOL_CHECKS`; add
  manager branches only for special payload structure or runtime behaviour.
- `tests/tools_runner.sh` first calls the packaged manager's public `health`
  command, then runs extended functional checks during offline qualification.
  It loads shared read-only helpers, without sourcing the manager CLI or taking
  over its traps and transaction state. A source-only, non-executable
  `tests/tools/mytool.sh` registers its suite automatically for a selected
  tool. Define `health_mytool()` with the release directory and disposable
  HOME as its two arguments; replace hyphens with underscores in function
  names. Invoke the packaged executable by its release path, prepare inputs
  under that disposable HOME, assert useful output or behaviour, and propagate
  failures. Tests must work without network access. Tools without a dedicated
  functional suite still receive the common presence and version checks.
  Bash always has an integration suite; uv's Python-management suite additionally
  requires selected Python.

Keep installer scenarios grouped by operation. Extend existing cases under
`tests/setup_tools/` for connected installation, archive handling,
ownership, recovery or locking, and under `tests/dotfiles_release/` for
verification, selection, HOME links, health or recovery. Extend their
`fixture.sh` when a fake executable or archive needs a new layout. For a
new tool, cover successful installation and the relevant missing or invalid
payload, plus a reduced selection that omits the tool and its configuration.
Changes to connected diagnostics or Bash integration belong in
`tests/bash_test.sh`; editor functionality stays under
`nvim2/.config/nvim2/tests/`.
`tests/setup_architecture_test.sh` protects source-only library behaviour and
the separation between catalog validation, recipes and CLI lifecycle.

No new top-level test runner is needed for an ordinary tool or OS.
`scripts/validate` already finds `tests/tools/*.sh` and the existing
installer scenario directories for linting. If a distinct new scenario really
needs a file, register its name in `tests/setup_tools_runner.sh` or
`tests/dotfiles_release_runner.sh`. A separate top-level `tests/*_test.sh`
needs both the shell-file list and a bounded `run_test` call in
`validate_scripts()`; merely creating that file does not run it.

During development, use the relevant existing scenarios, then run full
repository validation:

```bash
bash tests/setup_tools_runner.sh install
bash tests/setup_tools_runner.sh archives
bash tests/setup_tools_runner.sh configuration
bash tests/dotfiles_release_runner.sh selection
bash tests/dotfiles_release_runner.sh verification
bash tests/dotfiles_release_runner.sh health
bash tests/dotfiles_release_runner.sh online
bin/task validate
```

In an isolated connected development VM, follow the
[connected setup](#connected-machine), install the new tool explicitly with
`./setup-tools mytool`, and rerun that command to check reuse.
`dotfiles-check` expects the complete current `TOOLS` selection, so install
that selection before its final check. For offline qualification, use a clean
committed test checkout containing the new tool and run
`bin/task test -- debian13` while debugging, then `bin/task test` for all
selected platforms before publication. The existing
[reduced tool selections](#complete-offline-release) can be used for occasional
smaller-package qualification. There is no need for a matrix of every possible
tool combination.

Neither `Taskfile.yml` nor `.github/workflows` needs a per-tool entry for
ordinary installation or release tests: they invoke the existing runners.
Repository validation tools are the separate exception described below.

### OS packages, plugins and editor tools

An OS-provided tool such as MC belongs in `system.env`, not
`TOOL_RELEASES`. Add or remove it in the appropriate common or family-specific
`SYSTEM_*_PACKAGES` role and update `SYSTEM_RUNTIME_COMMANDS`,
`SYSTEM_SETUP_COMMANDS` or `SETUP_PREREQUISITES` when the required commands
change. Runtime-role packages are host prerequisites, not copied binaries in
the archive; build-role packages prepare the builder; setup-role packages
prepare connected hosts. Review fixed system diagnostics in
`bash/.bash_aliases` when changing that baseline and extend
`tests/setup_system_test.sh`. Package-list removal does not uninstall
already installed OS packages.

An asdf runtime needs its records in `TOOL_RELEASES` and a pinned
`repository|commit` entry in `ASDF_PLUGINS`. Those keys already determine
the supported arguments and default runtime list in `setup-asdf`; no new
entry script is needed. A delegated `version|-|-` record is valid for
asdf and cannot supply a directly installed
online or offline tool. Asdf itself is not included in offline releases.

A tmux Git plugin uses `TMUX_PLUGINS` and the desired online/offline lists.
Its shared checkout installer is `scripts/setup-tmux-lib`; no per-plugin
installer is needed. For a new plugin, extend the explicit commit-field,
dependency and private-payload cases in `setup-tools-lib`, the manager's
metadata allowlist and the tmux startup configuration. Extend
`tests/setup_tools/plugins_test.sh` and the relevant tmux/release checks.
The existing [tmux plugin instructions](#tmux-plugins) cover pins and loading.

For a Mason tool, edit `M.tools` and, where needed, `M.tool_probes` in
`nvim2/.config/nvim2/lua/custom/lsp.lua`, then configure its LSP, formatter,
linter or debugger in the existing editor modules. Do not add a private
Mason package to the standalone lists just to satisfy editor checks.
`custom.tools` derives inventories and provider dependencies; the builder
and manager consume them. Existing npm, PyPI and Go providers use the
declared Node.js, Python and Go runtimes. A tool needing another external
runtime also needs its requirement in `custom.tools.requirements()`,
corresponding runtime support and acceptance in `verify_nvim_inventory()`
in `setup-tools-lib`. Add a representative editor functional case for a
new feature. Python-backed package changes also require
`bin/task update:python-locks`; never edit generated locks by hand.
Follow the [language guide](../nvim2/.config/nvim2/guide.md#temporarily-disabling-language-support)
for disabling activation, optional `MasonUninstall`, restoration and checks,
and the [offline editor notes](../nvim2/.config/nvim2/offline-releases.md#language-dependencies-and-reduced-tool-selections)
for private runtimes and inventories.

A tool used to validate this repository needs an entry in
`VALIDATION_TOOLS` and an independent pin in `VALIDATION_RELEASES` in
`validation.env`, supported artifact preparation in `setup-recipes-lib`, and,
when necessary, an internal Task bootstrap dependency using
`scripts/install-validation-tool`. Extend
`tests/install_validation_tool_test.sh` for new installation behaviour.
Development-tool and Mason pins do not select the repository validation version.

## Complete offline release

For a restricted host, use the complete platform artifact. This is the only
supported offline installation route; `setup-tools` and `setup-asdf` are not
used. The default artifact contains an immutable snapshot of shared and selected
configuration together
with Neovim and its complete tool set, Node.js, private standalone Python, the
complete Go SDK,
ripgrep, fd, tmux and plugins, htop, Oh My Posh, gh, k9s, kind, uv/uvx, zoxide,
kubectx, kubens, kubeconform, Kyverno, Trivy, Task, actionlint, ShellCheck,
yamllint, yq, fzf and Terraform,
plus every kubectl and Helm version listed in `tools.env` and the ready-to-run
`helm schema` plugin `2.4.0` with its license material.
Each release owns its complete tool payload, even when another retained release
contains the same versions. Asdf, its plugins and its shims are not part of the
offline package. Optional online `setup-asdf` remains available independently.

Edit `OFFLINE_RELEASE_TOOLS` to remove tools from the next package. The list
selects binaries, launchers, plugins and tool configuration. The archive contains
the shared Bash/Git/SSH/Vim files and selected tool packages, rather than the whole
repository. For example, removing k9s removes its binary, configuration and skins;
unselected MC configuration and local-share files are not bundled.

Nvim stays in the default list but can be removed as a whole, including its
configuration, plugins, Mason payload and editor tests. Its default configuration requires
Node.js, Python, Go, ripgrep and Terraform. Terraform is required by the editor's
Terraform formatter and language server. These are separate tools: removing
Nvim does not automatically remove them. Reduced editor requirements follow
its selected Mason packages and active features. Tool-list dependencies are
checked before downloads; editor dependencies are checked after plugin bootstrap,
before Mason installation.
`yamllint` currently uses Nvim's Mason environment, so remove it too when omitting
Nvim. Tmux plugins require tmux, and `helm-schema` requires Helm. npm belongs to
Node.js. Private Mason dependencies remain owned by the editor: removing the
standalone actionlint tool leaves the editor's independently pinned copy.

When selected, Mason's `ansible-lint` environment contains
the locked `ansible-core`; offline builds expose `ansible`, `ansible-config` and
`ansible-playbook` through `share/nvim2/mason/bin`. Bash adds that directory to
PATH. These commands disappear when that Mason package is omitted. `setup-system` does not
install Ansible. Online Ansible LSP finds these commands directly in Mason's
venv, after any commands supplied by the project's environment. That venv is
not added to the interactive shell PATH; expose project Ansible commands
through an activated project venv when needed.

To pause editor support or optionally remove Mason packages on a connected
machine, follow the [language support guide](../nvim2/.config/nvim2/guide.md#temporarily-disabling-language-support).
The [Nvim offline notes](../nvim2/.config/nvim2/offline-releases.md#language-dependencies-and-reduced-tool-selections)
describe how builder, installer and functional tests follow those declarations
for reduced editor tool selections.

Archives record the complete selection, including tmux plugins, in
`OFFLINE_RELEASE_TOOLS`. Required version fields, payload checks and public links follow
that selection. Selecting fewer tools
removes obsolete managed HOME links and restores saved originals in the same
transaction as switching `current`; it preserves user state and caches.

The manager supports one current archive contract, without `RELEASE_FORMAT`
or `NVIM_TOOLS_FORMAT` flags. Archives containing those flags, implicit plugins
or missing Neovim inventories are rejected. Rebuild from current sources
instead of adding migration branches or rewriting published archives. For an
installation using an older contract, use its original embedded manager to
uninstall retained releases before installing the rebuilt package. Keep user
state and caches.

The private Python interpreter lives only under `tools`. Adding `current/bin`
to PATH does not select it as your shell's Python.

The supported setup and qualification platforms are `debian-13-x86_64`,
`ubuntu-24.04-x86_64`, `ubuntu-26.04-x86_64` and `amzn-2023-x86_64`.
For a complete local qualification, run from a clean committed checkout on a
connected machine with Docker access:

```bash
bin/task test
# Show usage and the location of the platform configuration:
bin/task --summary test
# Build and qualify just one platform:
bin/task test -- ubuntu2404
```

The task uses `scripts/dotfiles-release-ci test` and the immutable images from
`release.env`. By default it builds every platform in
`OFFLINE_TEST_PLATFORMS` in parallel, waits for all builds to finish, then
prepares and verifies successful builds in parallel.
Each installation uses a fresh container, an ordinary user and `--network none`.
Each job verifies the archive, installs it with the downloaded manager, then
runs `tests/tools_runner.sh` from the trusted workflow checkout.
That CI-only checker runs the full functional suites and verifies installed
content before and after them. It is not needed on the target host.
The task prints a retained `/tmp/dotfiles-qualification.XXXXXX` directory:
`output/PLATFORM/` contains the archive and standalone installer with their
`.sha256` files;
`dotfiles-evidence/PLATFORM/` contains build, prerequisite-preparation and
offline-install logs, including complete `build-only.log` and `verify.log`
output for each worker; `summary.md` contains successful package sizes and hashes.
Failure on one platform does not stop the others. The task prints each
platform's build and verification exit codes and log directory at the end,
and adds these results to `summary.md`. Verification is skipped only for a
platform whose build failed. The task returns a failure after all work finishes
if any selected platform failed. It preserves packages and logs from successful
and failed jobs while cleaning up containers and temporary runtime images.
No GitHub release or credentials are required, and nothing is published.
`task validate` runs the repository's local
fixture tests, including reduced tool lists, rather than this full qualification.

### Managing OS support and offline publication

Platform selection and image configuration live in `release.env`:

- `PLATFORM_ALIASES` maps names such as `ubuntu2404` to platform IDs such as
  `ubuntu-24.04-x86_64`. Both `task dev -- NAME` and `task test -- NAME` use it.
  `DEFAULT_DEV_PLATFORM` selects the alias used by `task dev` without an argument.
- `LXD_IMAGES` selects development VM images by platform ID.
  `LXD_IMAGE_SHA256` is needed only for direct QCOW2 downloads, currently Amazon
  Linux. Remote LXD cloud images do not use this checksum map.
- `DOCKER_IMAGES` pins the container images used for building and qualification
  by platform ID. These are independent of the VM images.
- `OFFLINE_TEST_PLATFORMS` selects the platforms built and installed by the
  default `task test`. Explicit qualification also requires membership in this
  list. `task dev` is independent of it.
- `OFFLINE_RELEASE_PLATFORMS` selects artifacts published by the GitHub
  offline-release workflow.

`Taskfile.yml` forwards the chosen name to the scripts; it contains no platform
map or image tags. VM resources such as CPU, memory, storage and network remain
Task variables. Host installation support remains in `scripts/setup-system-lib`,
`system.env` and `setup-system`. The builder, installer and validators share
`system_validate_platform_name()` and `system_validate_release_host()` from
`setup-system-lib`; the generated standalone manager includes that library.
Supported OS identities are declared once there, separately from image pins
and the lists selecting development, qualification and publication.

Keep at least one qualification platform; the release list may be empty.
The release list must be a subset of the test list. `scripts/validate` and the
release workflow reject duplicates, unknown qualification platforms and release
platforms that are not tested. The first release platform also supplies the
standalone `dotfiles-release` asset, so keep a stable primary platform first.

Ubuntu 24.04 remains supported and qualified, but its artifact publication is
currently paused. This is represented by one commented line in
`OFFLINE_RELEASE_PLATFORMS`. To publish it again, uncomment that line. Do not
remove its image entries, alias, test-list entry or setup logic. Run
`task validate` and `task test -- ubuntu2404` before triggering the release
workflow. Commenting every release-list entry disables artifact publication;
local qualification continues to follow the test list. Existing GitHub release
assets are not deleted.

To stop qualifying an OS while keeping its development VM and host support,
comment its entries in both offline platform lists. Keep its alias and images.
To change the default development VM, edit only `DEFAULT_DEV_PLATFORM`, for
example `DEFAULT_DEV_PLATFORM=ubuntu2604`. An image change affects newly created
VMs; existing VMs continue to be reused with their current image and resources.

The `runs-on: ubuntu-24.04` values under `.github/workflows` select GitHub-hosted
CI runners. They do not select Ubuntu 24.04 as an offline package target and do
not need to change when its artifact publication is paused.

To add a future platform such as Ubuntu 28.04 or Debian 14:

1. In `scripts/setup-system-lib`, extend `system_validate_platform_name()`
   with the new `ID-VERSION_ID-x86_64` platform and `system_install_docker_repository()`
   for its Debian/Ubuntu repository suite. Review runtime, build and setup
   package roles and expected commands in `system.env` against the new
   distribution, and update the supported-host help in `setup-system` and
   the platform help in `scripts/build-dotfiles-release`.
   `system_validate_release_host()` derives the expected OS ID and version
   from the platform name, then checks `/etc/os-release` and x86-64.
   The builder, installer, CI and catalog validation need no separate
   platform cases.
2. Review package-family support in `scripts/setup-system-lib` and `system.env`.
   A new Debian/Ubuntu version reuses the existing package family. An entirely
   new distribution family also needs package roles and package-manager support
   in `system.env` and `setup-system-lib`, plus the runtime/Docker arrays
   embedded by `scripts/build-standalone-script`. Add that family's bootstrap
   prerequisites in `scripts/dev-vm-setup`; its existing Debian/Ubuntu branch
   already covers new versions of those distributions.
3. In `release.env`, add its short alias to `PLATFORM_ALIASES`, its pinned
   Docker image to `DOCKER_IMAGES` and its VM image to `LXD_IMAGES`.
   Add `LXD_IMAGE_SHA256` only for a direct QCOW2 download. The tasks, CI image
   selection and image validation use these maps without OS-specific edits.
4. Add focused cases to `tests/setup_system_test.sh`,
   `tests/dev_vm_test.sh` and `tests/dotfiles_release_ci_test.sh`.
   Cover archive platform acceptance and host mismatch in the existing
   `tests/dotfiles_release/verification_test.sh` scenarios and fixtures.
   These are extensions to existing scripts; a new `setup-OS`, `dev-OS`
   or top-level test script is not needed. Update the
   supported-platform text in `README.md`, this guide,
   `maintenance/tool-updates.md` and
   `nvim2/.config/nvim2/offline-releases.md`.
5. Add it to `OFFLINE_TEST_PLATFORMS`, run `bin/task validate`, and
   check connected setup inside `bin/task dev -- NEW_ALIAS` using
   `./setup-system`, `./setup-tools` and `dotfiles-check` after linking
   the configuration. Run full local offline qualification with
   `bin/task test -- NEW_ALIAS`. Add it to `OFFLINE_RELEASE_PLATFORMS`
   only after these checks succeed.

Fully retiring an OS requires reversing those additions in `release.env` and
`scripts/setup-system-lib`, updating the help in `setup-system` and
`scripts/build-dotfiles-release`, then removing its focused cases and
supported-platform documentation listed above. If it is the default VM, select
another alias in `DEFAULT_DEV_PLATFORM`. Package arrays in
`system.env` only need removal when the retired OS was the last member of that
distribution family; also remove that family's embedded arrays from
`scripts/build-standalone-script` and its bootstrap branch from
`scripts/dev-vm-setup` when retiring the whole family.
`.github/workflows/dotfiles-release.yml` receives its
artifact matrix from the release list, so it has no OS target list to edit.
The shared platform rules are embedded so the standalone manager can recognize
an archive without a checkout. Task aliases, VM and container image
metadata, publication and default qualification are centralized in `release.env`.
The workflow reads `DOCKER_IMAGES` from the selected release's source snapshot.
Snapshots with older individual image variables are unsupported; use a release
tag from current sources.

To build only one platform, select its image from `release.env` and keep the
checkout read-only in the builder:

```bash
set -euo pipefail
test -z "$(git status --porcelain --untracked-files=normal)"
source scripts/setup-lib
source scripts/setup-system-lib
load_platform_config "$PWD/release.env"
platform=debian-13-x86_64
image=${DOCKER_IMAGES[$platform]}
output=${1:-"$PWD/offline-output"}
mkdir -p "$output"

docker pull "$image"
timeout --signal=TERM --kill-after=30s 5400s docker run --rm --init \
  --volume "$PWD:/workspace:ro" \
  --volume "$output:/out" \
  --env BUILDER_IMAGE="$image" \
  "$image" \
  bash /workspace/scripts/build-dotfiles-release \
    build "$platform" /workspace /out
```

The builder verifies every downloaded archive, compiles tmux and htop against the
target distribution libraries, starts from empty Neovim data, and runs the
tool-enabled editor checks. The official Node archive initially contains its
upstream npm, then the builder installs the separately pinned and hashed npm
archive. The standalone CPython runtime contains the standard library but not
ansible-lint, yamllint, ansible-core or debugpy. Separate generated hashed locks and a
complete wheelhouse supply those dependencies. The target installer creates
ordinary isolated venvs at their final retained paths using only those wheels.
It does not need sudo, a distribution Python, a host C compiler or network
access. Go projects compile with the bundled SDK; CGO projects still require
their own compatible C toolchain and libraries.

Python debugging adds four locked Neovim plugins and Mason's pinned `debugpy`
package. The builder supplies its hashed wheel and portable launchers; the
existing installer recreates its isolated venv at the final retained path.
It adds no Python-specific OS packages or project runtimes. For a connected
Nvim2 installation, run
`:Nvim2ToolsInstallSync` after installing the configuration. The debugger's Python
is separate from a project's `.venv`; project dependencies still belong to the
project and are not bundled. No browser, GPU or TypeScript debug adapter is
required. See the [Python debugger guide](../nvim2/.config/nvim2/guide.md#python-debugger).

Go adds pinned gopls, goimports, golangci-lint and Delve through Mason, the
locked `nvim-dap-go` plugin and Go/manifest Treesitter parsers. Mason builds
gopls, goimports and Delve with the bundled SDK in the connected builder;
golangci-lint uses its upstream binary. These tools are built with CGO disabled
and arrive ready to run on the restricted host. No additional OS package or
`setup-asdf` dependency is added. The Go launcher pins the physical SDK with
`GOTOOLCHAIN=local`, preventing automatic toolchain downloads. Application
modules and a project's different SDK version are not bundled: prepare vendor
or module-cache dependencies separately before disconnecting. See the
[Go guide](../nvim2/.config/nvim2/guide.md#go-development-and-debugger).

`scripts/build-dotfiles-release` is the connected build and runtime-image
preparation entry point. Each archive and GitHub release includes standalone
`dotfiles-release` and its `.sha256` file; no separate offline setup script is
published. `scripts/build-standalone-script` generates the manager from the
matching release sources: runtime and Docker configuration from `system.env`,
tool probes from `tools.env`, `scripts/setup-lib`, `scripts/setup-system-lib`,
`scripts/setup-tools-lib`, `scripts/dotfiles-release-lib` and the
`scripts/dotfiles-release` CLI. `##### BEGIN SOURCE #####` and
`##### END SOURCE #####` comments identify each embedded block. Edit the
repository sources, not generated scripts; there is no second offline
installer implementation. The published manager is extracted from the
qualified Debian archive and is shared by all four platforms. The manager
has seven commands: `setup`, `verify`, `list`, `health`, `install`, `uninstall` and `set`.
None needs the builder or a Git checkout on the target.

Release preflight uses GitHub asset names to select incomplete platforms without
downloading packages. Before publishing missing assets, the platform job verifies
the existing archive, checksums and standalone manager. Completing a missing
manager or checksum does not rebuild the archive. It always extracts the
manager from the matching archive, never from a newer workflow checkout.
A published script or checksum that differs is rejected, not overwritten.

The artifact contains selected paths from a Git archive of the matching commit,
without the repository history. The default selection also contains the full
Neovim runtime tree, pinned plugin Git metadata, parsers, queries, Mason receipts,
tmux plugins, Python locks and the temporary wheelhouse.
`release.env`, `build-manifest.txt` and `SHA256SUMS` record source identity,
layout, versions, inputs and content.
The generated payload-root `release.env` is distinct from the source repository's
`release.env`, which contains builder image pins and is not bundled.
After venv creation the retained installation removes the wheelhouse and
records a new local manifest covering file contents, modes and symlink targets.

Download the manager, matching platform archive and their `.sha256` files from
the same GitHub release, then prepare the target while approved repositories
are available. No repository checkout, separate config or helper file is needed.

`dotfiles-release setup` installs the release's system prerequisites
and Docker if absent, not its bundled tools or development packages.
It still needs access to apt/dnf and, for a new Debian/Ubuntu Docker
installation, Docker's repository. It detects the host OS without an archive
or platform argument and never installs or activates a release. The connected
`setup-system` entry point uses the same `scripts/setup-system-lib` with its
broader normal-host package set; there is no copied offline implementation.
Neither selects a tool list: `setup-tools` selects `TOOLS`, and the builder selects
`OFFLINE_RELEASE_TOOLS`. The archive retains the metadata key `OFFLINE_RELEASE_TOOLS`.
It lists the complete selection, including Git plugins; the installer never
adds tools that are absent from that list.
Selected plugin commits are recorded in `release.env`; repository and commit
identities also remain in `build-manifest.txt`, with files in `SHA256SUMS`.
No published archive, tag or release needs to be rewritten.

On a connected machine, download these release assets into one directory with
`gh`, then transfer them to the target:

```bash
tag=dotfiles-COMMIT
platform=debian-13-x86_64
archive=dotfiles-COMMIT-$platform.tar.gz
gh release download "$tag" --repo surbanski-nr/dotfiles \
  --pattern dotfiles-release --pattern dotfiles-release.sha256 \
  --pattern "$archive" --pattern "$archive.sha256"
```

Replace `COMMIT` in the tag with its actual suffix and in the archive name with
the first 12 characters of the full commit SHA.

On the target, first verify the installer and prepare OS packages while the
repositories are reachable. Run as the intended ordinary user so new Docker
group membership is assigned correctly:

```bash
sha256sum --check --strict dotfiles-release.sha256
bash ./dotfiles-release setup
```

Review any warnings and rerun `setup` if preparation was incomplete. On an
already prepared host, skip this step and install directly; no `--skip-system`
flag is needed. The manager embeds its runtime package lists and helpers, so
this route needs no dotfiles checkout or separate setup script.

After disconnecting external networking, run the downloaded installer as the intended
ordinary user. It derives identity from that account and does not require a
particular user name, UID or `/home` path:

```bash
sha256sum --check --strict dotfiles-release.sha256 \
  dotfiles-COMMIT-debian-13-x86_64.tar.gz.sha256
bash ./dotfiles-release verify \
  "$PWD/dotfiles-COMMIT-debian-13-x86_64.tar.gz"
bash ./dotfiles-release install \
  "$PWD/dotfiles-COMMIT-debian-13-x86_64.tar.gz"
source "$HOME/.bashrc"
hash -r
dotfiles-release list
dotfiles-release health
```

`verify ARCHIVE` checks the single release root, safe archive paths and links,
required payload, complete metadata and file inventory against `SHA256SUMS`.
It reads the platform from payload-root `release.env`, not the archive name,
so renaming the archive is harmless. It does not require a matching host
platform, run package programs, install files or change the user's HOME.
Checksums detect corruption; they do not make an untrusted archive trustworthy.

`install ARCHIVE` repeats structural verification and requires the package's
platform to match the host. It never runs `setup`, installs OS packages, downloads
tools or uses sudo. It checks system prerequisites and managed-path
conflicts, creates isolated Python venvs at their final retained paths, removes
the wheelhouse and records `installed.sha256`, `installed.modes` and
`installed.symlinks`. These local manifests cover generated venvs as well as
the original payload. Light runtime checks cover Python isolation and
dependencies, bundled tool versions and the Helm schema plugin. Install then activates the
release through the same code used by `set ID`. Reinstalling an unchanged
retained ID reuses it after integrity and runtime checks.

Extended functional cases are grouped by tool in `tests/tools/` and run by
`tests/tools_runner.sh` according to the package's declared selection.
Bash integration checks follow that selection too; full Nvim tests stay in the
editor's test directory. A missing selected program is a failure, not a skipped
test. Installer tests remain grouped by verification, installation, switching,
recovery, integrity and locking. The functional checks still run
with networking disabled before publication, but are not part of target
installation or archive verification. There is no `--skip-tests` switch.

The fast installer tests cover empty-list rejection, single-tool selections,
smaller tool lists and switching back to the full selection. `task test` qualifies
the current `OFFLINE_RELEASE_TOOLS` on the requested platforms; it does not run
a matrix of every tool combination. For occasional checks of smaller real
archives, use four cumulative selections:

```bash
tmux_profile=(tmux tmux-sensible tmux-resurrect tmux-continuum)
search_profile=("${tmux_profile[@]}" fzf zoxide rg fd)
editor_profile=(
  "${search_profile[@]}"
  nvim nodejs python go terraform
)
kubernetes_profile=(
  "${editor_profile[@]}"
  k9s kind kubectl kubens kubectx helm
)
```

Put one of these selections in `OFFLINE_RELEASE_TOOLS` in a clean committed
test checkout and run `bin/task test -- debian13` there. Bash/Git/SSH/Vim are
shared configuration and do not need entries in the list. The editor selection
retains its private Mason tools even though standalone development tools and
`yamllint` are omitted. Helm's optional `helm-schema` plugin is also omitted in
these examples. The four checks build archives, verify them, install them on a
minimal runtime and run the selected functional tests without network access.

`health [ID]` checks the installed structure, content, modes, symlinks and those
same light runtime probes, defaulting to `current`. For the selected release it
also checks that all managed HOME links exist, point through `current` and have
valid targets. An inactive ID is checked only within its own payload; its tools
must resolve in the isolated release PATH and run without borrowing host tools.
Health does not activate a release, repair links or run the extended CI suite. Runtime probes
use a disposable HOME and a UTF-8 locale without touching user data. An error
leaves the current selection unchanged. `install` and `set` run the shared
probes before activation; a failed candidate therefore never becomes current.

For diagnostic work, `install --skip-health ARCHIVE` and
`set --skip-health ID` skip only runtime probes. Archive verification,
platform compatibility, installed integrity, path conflict checks, backups
and failure cleanup still apply. The bypass is reported explicitly. It does
not permit editing the retained payload or regenerating its manifests; repair
user configuration outside the release, or build and install a corrected
archive. A later `health` checks the selected release again.

These are installation checks, not a repeat of development qualification.
Health does not load personal shell startup files or examine aliases, shell
command caches, intentional `~/bin` overrides or project venvs. It cannot
change the PATH of an already running shell; reload `.bashrc` and run `hash -r`
after selection. Full Bash initialization, plugin features, formatting, LSP
and debugger behavior remain covered by the offline CI functional checker.

Releases are retained under `~/dotfiles-releases/dotfiles-COMMIT`. Override the
store with an absolute `DOTFILES_RELEASE_ROOT` when needed. `current` is the
only selection link; there is no `previous`, ownership database, pending
journal or completion flag. `list` displays prepared offline directories with installed manifests and the
prepared `online` installation, marking the selected ID. An unfinished import is not listed and
cannot be selected; remove its exact ID with `uninstall ID` before retrying.
`set` validates metadata, manifests and runtime rather than trusting a flag.

Before replacing a managed path, activation moves its original file, link or
directory to `<path>.before-dotfiles-release`. Backups stay on the same
filesystem and survive later selections. A conflicting existing backup or
symlink parent stops activation; foreign links are backed up like other
originals. This deliberately needs no setup-tools or bstow ownership records.
Only configuration links, packaged k9s skins and the three tmux plugin paths
are managed. Release commands are available directly from `current/bin` on
PATH. `~/bin` is user-owned in both flows: the manager never creates it, scans
its contents, backs up its files or changes its links. Private k9s files,
kubeconfig inputs and unrelated tmux plugins are also untouched.

Use the manager for every selection change:

```bash
dotfiles-release list
dotfiles-release set dotfiles-COMMIT
dotfiles-release health
dotfiles-release health dotfiles-OLDERID12
dotfiles-release uninstall
dotfiles-release uninstall dotfiles-INACTIVE12
```

`set ID` selects an installed unit, including older releases. It never installs
an archive. `uninstall ID` deletes that retained directory, including damaged
or unfinished imports. If it is current, uninstall also removes the release's
configuration links, restores adjacent original-file backups and removes `current`;
it does not automatically select another release. Plain `uninstall` means the
current ID. Other retained releases remain available for a later `set`.
Uninstall preserves a managed path that the user replaced with another file
or foreign link; its adjacent original backup then stays for manual recovery.
Close processes still using the ID before deletion. The manager does not guess
process ownership or terminate applications. Keep the downloaded standalone
script outside managed links so it remains available after active uninstall.

`install`, `set`, `uninstall` and `health` share one non-blocking lock on the store
directory, with no persistent lock file. `verify` and `list` are read-only and
do not take that lock. Health locks an existing store only to prevent deletion
or switching during diagnostics and does not create a store. Normal failures,
Ctrl+C and TERM undo changed links and restore originals using a temporary
in-memory undo list. A failed new install
removes its candidate after a successful undo. If undo itself fails, the
manager preserves the candidate and temporary backups and reports their paths.
There is no automatic journal recovery after SIGKILL or power loss. Inspect
adjacent backups and temporary link paths, select a known-good ID with `set`
and explicitly remove an unfinished ID before reinstalling. Do not hand-edit
installed payloads or generated manifests, and never move a completed venv.

When migrating an installation created by the older stateful manager, first
use a saved copy of that manager to run its plain `uninstall` and restore the
original baseline. Its backup names and ownership database are not read by the
new manager. Then install a newly built archive with the new downloaded script.
Stale legacy state is not used for recovery. No automatic migration of old
`~/bin` links is performed; the cleanup command below is optional.

The shell PATH contains `current/bin` literally, and configuration links also
point through `current`. An ordinary offline A-to-B upgrade needs no migration
or manual deletion of command links: install B or select it with `set`. The
PATH cleanup on Bash startup removes physical release paths inherited from
older application processes; it does not modify either release's payload.
The Nvim, tmux and Kubernetes client launchers resolve
one physical release when each process starts. After a switch, reload
Bash with `source "$HOME/.bashrc" && hash -r`; new shells and applications use
the new release, while an existing Nvim process and tmux server remain on their
old physical configuration and plugins. `prefix` + `Shift-R` reloads that
server's physical config through `source-file -F`; it does not switch an A
server to B. Finish or safely stop the old server before expecting a new one to
use the newly selected release.

Mutable Nvim state, including ShaDa, undo, project marks and
Telescope history, stays under `XDG_STATE_HOME` or `~/.local/state/nvim2`.
The first activation copies legacy Telescope history files only when
the new destination is absent and preserves the source. zoxide data,
tmux-resurrect sessions, caches, kubeconfig and credentials also remain outside
the immutable payload. The Nvim launcher remembers the user's original
`XDG_CONFIG_HOME` and `XDG_DATA_HOME` before selecting physical release data.
An interactive terminal Bash restores those values before integrations start.
Direct Nvim jobs use an explicit `_ZO_DATA_DIR`, defaulting to the user's
original data home, so zoxide never writes into retained release data. Explicit
`_ZO_DATA_DIR`, paths with spaces, nested launches and another `NVIM_APPNAME`
remain supported.

The offline eslint_d launcher runs its bundled ESLint fallback without a daemon,
because native daemon state would modify the immutable installation. A project's
own ESLint still uses the native daemon. CI qualification verifies installed
content both before and after its functional checks.

The release does not own anything in `~/bin`. Standalone Python is private to
its tool payload, available explicitly as `current/tools/python/bin/python3`;
neither `python` nor `python3` is exposed in `current/bin`. kubectl and Helm
are public release commands.
Cluster access still needs the appropriate network, kubeconfig, credentials
and any external authentication executables. Krew plugins and optional k9s
helpers are not automatically bundled.

### Selecting a bundled Kubernetes client

The first kubectl or Helm record in `tools.env` is the default. The builder
includes every record for those two tools; other tools use only their default.
Launchers resolve one physical release and run its client without using asdf,
searching `.tool-versions`, downloading tools or detecting the cluster version.

```bash
kubectl version --client
helm version --short

# Select an exact version for one command:
KUBECTL_VERSION=1.34.12 kubectl get nodes
HELM_VERSION=3.21.0 helm list

# Select versions for this shell and commands started from it:
export KUBECTL_VERSION=1.34.12 HELM_VERSION=3.21.0
kubectl get pods
helm list

# Return to defaults from the active release:
unset KUBECTL_VERSION HELM_VERSION
```

Unset or empty variables select the default. A version may use one optional
leading `v`: `HELM_VERSION=v3.21.0` and
`HELM_VERSION=3.21.0` select the same executable. The Helm default remains
`4.3.0`; `3.21.0` is also bundled. An invalid or unbundled
version fails clearly, without falling back to another tool
provider. Explicit binaries such as `current/bin/kubectl-1.34.12` also work
and are on the release PATH alongside the canonical client launchers.
`release.env` records ordered `KUBECTL_VERSIONS` and `HELM_VERSIONS` lists.
Installation checks every version and the default independently of the
caller's selection. CI also reads an isolated kubeconfig and renders a local
chart offline.

Client selection is inherited by subprocesses that invoke `kubectl` or `helm`
through these launchers. It does not change Kubernetes/Helm libraries embedded
inside other programs. kubectl must be within one minor version of the cluster
API server, as described in the upstream version-skew policy.

Bash keeps asdf shims below `current/bin` in both deployment workflows.
Bundled commands take priority over those shims; commands missing from the
release can fall back to asdf. Executables in `~/bin` take priority over both
providers, so review intentional overrides with `type -a TOOL`.

### Helm schema plugin and project validation

Managed Helm defaults to `share/helm/plugins` in its resolved release when
`HELM_PLUGINS` is unset or empty. The packaged `schema` plugin is built from
the verified `losisin/helm-values-schema-json` release with a minimal manifest
without installation/update download hooks. Host plugins are left in place.
A nonempty `HELM_PLUGINS` selects your own complete plugin directory; it opts
out of the bundled default. A direct versioned Helm executable bypasses that
launcher policy. Older releases without the plugin keep their original
discovery and never borrow a plugin from a newer release.

CI qualification selects the bundled plugin directory explicitly, checks the version
and manifest, generates a local schema with `$ref`, `--bundle` and
`--bundle-without-id` for every bundled Helm version, and exercises yq YAML
documents and jq overlay merging. These checks use no network or user plugins.
Missing or wrong-version tools prevent activation; broken functional behavior
fails CI qualification before publication.

Switch between retained packages with `dotfiles-release set ID`. Both packages
must use the current archive contract described above; rebuild packages with
obsolete layouts. Let the manager update selection; do not edit retained
payloads or `current` by hand.

For NetReveal chart validation, offline means delivery of executables.
Chart repositories, schema endpoints and project pip dependencies may still
use the network. Run validation in a disposable project clone because it
cleans generated outputs, builds dependencies and regenerates schemas. From
that project's root, reread `tool-versions.env` and select its pins for the
whole Task invocation, not just one helper:

```bash
# Create this environment only if it does not already exist.
if [[ ! -e .venv-dotfiles ]]; then
  "$HOME/dotfiles-releases/current/tools/python/bin/python3" -m venv .venv-dotfiles
fi

(
  export PATH="$PWD/.venv-dotfiles/bin:$HOME/bin:$HOME/dotfiles-releases/current/bin:/usr/bin:/bin"
  unset HELM_PLUGINS
  export HELM_CONFIG_HOME="$PWD/.validation-helm/config"
  export HELM_CACHE_HOME="$PWD/.validation-helm/cache"
  export HELM_DATA_HOME="$PWD/.validation-helm/data"
  set -a
  source ./tool-versions.env
  set +a
  python3 --version
  helm version --short
  helm schema version
  yq --version
  jq --version
  task --version
  kubeconform -v
  task validate
)
```

Inspect and reuse an existing suitable `.venv-dotfiles`; never replace it
silently. The private release interpreter is Python `3.12.12`; no public
`python3` is exposed on the release PATH. For PR parity, run `task split-generate` before
`task validate` in the same subshell; its `PyYAML==6.0.2` download is allowed.
Task `3.53.1` and kubeconform `0.8.0` keep their defaults. Their version
differences from project pins need a real workflow run, not an automatic
downgrade. No chart/schema mirror, Trivy database or live cluster is added.

### User executable overrides

`~/bin` holds your trusted tools, wrappers and executable overrides. Bash
puts an active `VIRTUAL_ENV/bin` first, then `~/bin`, then the selected
release's `current/bin` and remaining providers. Nvim2 keeps the same user
priority ahead of its physically pinned release and Mason tools. Missing
directories are ignored safely, so the connected flow works without a release
store. Bash uses the same provider order whether its configuration comes from
the repository or a release. It does not detect a repository/release mode or
automatically disable asdf; existing shims remain below `current/bin` as a fallback.
For a nondefault store, export `DOTFILES_RELEASE_ROOT` before starting or
reloading Bash; its location is not inferred from the configuration.
Switching between repository and release deployment is a manual choice, not
a startup migration.
Connected `setup-tools` and `setup-asdf` publish commands in `online/bin`;
the shared manager selects them through `current/bin`. Both flows leave `~/bin`
untouched. The old `bin-extras` directory
is no longer added to PATH. The private `~/.extras` configuration hook is separate.

```bash
mkdir -p "$HOME/bin"
# Put an executable here using the command name to override.
source "$HOME/.bashrc"
hash -r
type -a helm
type -P helm
```

Your own `helm` bypasses the release launcher's version selection and plugin
defaults. Its owner supplies that behavior. Remove or move an override and run
`hash -r` to return to the managed executable; reinstalling is unnecessary.
New tmux panes load Bash normally. Existing panes need the same deliberate
reload. Noninteractive jobs and shells that do not load this configuration
receive their inherited PATH.

To start the offline Nvim2 without user-bin overrides, use:

```bash
DOTFILES_IGNORE_USER_BIN=1 "$HOME/dotfiles-releases/current/bin/nvim"
```

In an existing Bash session, export that variable and reload `.bashrc` to
rebuild PATH. Prefixing an arbitrary command with the variable does not rebuild
its inherited PATH. Release runtime checks, builds and repository checks enforce this
setting so local replacements cannot hide a broken payload. With either online
or offline selected, `dotfiles-check` delegates to its managed `health` check.
Online checks use saved `TOOLS` and the optional asdf catalog; offline checks use
saved `OFFLINE_RELEASE_TOOLS` and the package's inventories. Removing a connected
tool takes effect after a full `setup-tools` run and `set online`; retained payloads,
provider data and separately stowed configuration remain. Managed health checks
ignore intentional `~/bin` overrides. Use `type -a TOOL` or
`type -P TOOL` to inspect your interactive selection.

Aliases, absolute executable paths and project-local tools such as
`node_modules` have their own selection rules. The offline launcher's core
Neovim runtime remains fixed; personal `NVIM_APPNAME` profiles retain their
own configuration. Older retained Bash/Neovim configurations can restore older
PATH behavior, and existing processes retain their inherited PATH after a
selection change. `set` and uninstall leave `~/bin` untouched.

Older installers may have left `~/bin/TOOL` links pointing through
`dotfiles-releases/current/bin/TOOL`. They still follow selection, but can
dangle when the new release lacks that tool. There is no automatic cleanup.
After reviewing `ls -la "$HOME/bin"`, this optional command removes only links
with the exact old release target and matching command name. It leaves your
executables, foreign links and `.before-dotfiles-release` backups alone. If
`~/bin` itself is a symlink, review its destination separately instead:

```bash
release_root=${DOTFILES_RELEASE_ROOT:-$HOME/dotfiles-releases}
if [[ -d $HOME/bin && ! -L $HOME/bin ]]; then
  for link in "$HOME/bin/"*; do
    [[ -L $link ]] || continue
    target=$(readlink -- "$link") || continue
    if [[ $target == "../dotfiles-releases/current/bin/${link##*/}" ||
      $target == "$release_root/current/bin/${link##*/}" ]]; then
      printf 'Removing %s -> %s\n' "$link" "$target"
      unlink -- "$link"
    fi
  done
fi
hash -r
```

Restore any original-file backups manually only after reviewing them. A
restored executable in `~/bin` takes priority over the release by design.

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

The [Nvim2 offline notes](../nvim2/.config/nvim2/offline-releases.md) describe the
editor-specific runtime, qualification checks and state behavior. `tool-updates.md`
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
uv venv --offline --no-python-downloads \
  --python "$HOME/dotfiles-releases/current/tools/python/bin/python3" "$HOME/offline-venv"
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

## Tmux redraws

The configuration enables synchronized redraws for `xterm-256color` clients.
Terminals supporting this mode display each redraw as one frame, including
cursor visibility changes, so activity in another pane does not flash the
cursor. Reattach the client after changing terminal features; the session and
pane processes keep running.

Reloads append these terminal entries again; duplicate entries are accepted.

## Tmux eye-break timer

Press `Ctrl+a`, release it, then press `t` to open the local eye-break timer
menu. This replaces tmux's built-in clock mode; the status bar still shows
the time. The timer starts disabled and uses 60 minutes by default:

- `s`: start, resume a paused timer, or start a new countdown after completion.
- `p`: pause and show `|| ◷ MM:SS`.
- `r`: reset to the configured duration and wait for Start.
- `m`: enter whole minutes from 1 to 1440 and immediately start a new countdown.
- `o`: hide and disable the timer.

The countdown appears as `◷ MM:SS` before the IP. The clock is a Unicode
character and does not require a patched font. While the timer is visible,
clock/date disappear below 90 columns and the IP disappears below 60; the hostname still
requires 160 columns. At the end, the countdown disappears and the entire
status bar becomes red with white text. This colour is the only completion
signal; there is no extra label or notification. It remains until you start
again, reset, set minutes, or turn the timer off.

The script supplies timer text and state to tmux's native status bar. Layout
and colours stay in `.tmux.conf`, alongside the existing IP and clock.

One timer is shared by all sessions and windows on the same tmux server.
Reloading the config preserves it. Time continues while clients are detached;
the completion colour appears when a client reattaches. Killing the server
clears its state. The timer uses the existing status refresh interval, normally
five seconds with tmux-sensible, so completion may appear up to one interval
late. Paused and disabled timers run no status job; there is no background
countdown loop. The local script is included in both connected installations
and offline releases and requires Bash and `flock` from util-linux.

Run its focused integration checks with a private tmux server and terminal:

```bash
timeout 60s bash tests/tmux_timer_test.sh
```

They also run as part of `task validate:tmux` and `task validate`.

## Tmux plugins

Connected setup and offline builds use the same pinned Git-checkout installer.
`TMUX_PLUGINS` in `tools.env` owns the repository and commit of each plugin;
`TOOLS` and `OFFLINE_RELEASE_TOOLS` select them and define startup order.
New offline releases freeze that selection and order in `OFFLINE_RELEASE_TOOLS` in
`release.env`, which the loader reads when starting tmux.
There is no TPM install/update step or first-session plugin download.

The normal `./setup-tools` installs the binary and all three plugins. Select
the complete tmux setup or an individual plugin explicitly with:

```bash
./setup-tools tmux tmux-sensible tmux-resurrect tmux-continuum
./setup-tools tmux-resurrect
```

Connected checkouts live under `online/share/tmux/plugins/PLUGIN`.
`set online` links selected plugins into `~/.tmux/plugins/PLUGIN`. Relocate the
store with `DOTFILES_RELEASE_ROOT`. Tmux plugin directories must not contain
whitespace: upstream save/restore commands embed their paths without shell
quoting. If HOME contains spaces, choose a store without spaces before setup;
configuration and user data may still live under HOME. The online loader uses
`online/share/tmux/plugins`, with `~/.tmux/plugins` as the bootstrap fallback.
`DOTFILES_TMUX_PLUGIN_DIR` is a runtime override for an independently managed
plugin root, not an installer destination. This replaces the TPM-specific
`TMUX_PLUGIN_MANAGER_PATH` setting.

The installer verifies the repository, selected commit and executable entry
point. It refuses symlinks, non-Git paths, different origins and tracked/staged
edits before installing any requested tool. Untracked and ignored files are
preserved; a conflicting file stops a checkout. A selected pin is reused without
network access. A failed clone leaves no partially published plugin directory.
Plugin-only requests prepare the online store and manager link without binary
ownership records. The common release-root lock serializes all installers.
Session data under `~/.tmux/resurrect` or the plugin's XDG data path is untouched.

Offline builds place the same checkouts under `release/share/tmux/plugins`.
The shared `tmux/.tmux/load-plugins.sh` reads the catalog beside the loaded
configuration and runs selected plugin entries directly.
For offline sessions it uses the launcher's physical release path, ignoring the
online plugin-root override. Startup and reload never fetch or update plugins.
An explicit `tmux -f FILE` is authoritative in both flows.

An existing `~/.tmux/plugins/tpm` is left untouched and is no longer loaded.
Start a new server when moving from TPM to this configuration: a server that
previously loaded TPM may retain its old key bindings until it exits.
Do not use TPM's former install/update keys to manage these pinned checkouts.

## Krew

Krew remains separate from `setup-tools`. Read its first release record,
download and verify `krew-linux_amd64.tar.gz`, extract `krew-linux_amd64`, then
install the manager:

```bash
set -euo pipefail
source scripts/setup-lib
source scripts/setup-catalog-lib
source scripts/setup-recipes-lib
load_tool_catalog "$PWD/tools.env"
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

`validation.env` owns `VALIDATION_TOOLS`, `VALIDATION_RELEASES` and
`YAMLLINT_VERSION`. Task and GitHub Actions install their check tools from
this manifest directly into the Git-ignored root `bin/` directory. Yamllint's
private Python environment lives under `bin/yamllint-VERSION`; `bin/yamllint`
links to its executable.
`VALIDATION_RELEASES[python]` independently pins the standalone Python runtime
used by all Python-backed validation. `install-validation-tool python` checks
the archive SHA-256 and installs it under `bin/python-VERSION`; `bin/python`
is a private directory link. Task prepares it automatically, and installing
Yamllint directly also prepares it. No `python` or `python3` executable shim is
created in `bin/`, `~/bin` or a release's `current/bin`.
Changes to development tools in `tools.env` or editor Python locks do not
select new repository validation versions.

OS prerequisites belong to the normal setup role in `system.env`, not the
validation version manifest. Run `./setup-system` to prepare `script` for
private terminals and `ps`/`pkill` for process checks and cleanup.
Debian/Ubuntu provide `script` through `bsdutils` and process tools
through `procps`; Amazon Linux uses `util-linux` and `procps-ng`. The minimal
offline runtime does not include repository-only validation prerequisites.

Validation uses `bin/python/bin` on every supported platform, including Amazon
Linux, so the OS Python version and its venv/pip packages do not affect it.
Normal setup still provides OS Python and venv support for connected Mason.
Yamllint venvs reference the versioned private interpreter, not the moving
`bin/python` link. A new Python pin rebuilds Yamllint's venv even if its own pin
is unchanged; installation failure preserves the previous venv and interpreter.
Previously published Python runtimes and venvs are kept because existing venvs
can still reference them. There is no ownership database or previous/pending state.

Tmux for configuration tests comes from the existing PATH, including the
selected installation's `current/bin` and user overrides in `~/bin`. Validation prepends
its private Python bin and pinned tool directory without hiding those providers.
Empty PATH entries are removed to avoid resolving programs from the working directory.

Run the repository checks through Task:

```bash
bash scripts/install-validation-tool task
bin/task validate
```

Release manager and connected tool tests run in separate scenarios with fresh
temporary homes. Run a focused scenario while investigating a failure:

```bash
bash tests/dotfiles_release_runner.sh lifecycle
bash tests/setup_tools_runner.sh recovery
```

Repository-owned shell sources are linted from their real checked-in paths.
`validate:bash` retains batch logic tests and also runs actual Bash prompt loops
on private pseudo-terminals. Those sessions exercise Ctrl-L, generated fzf
Readline bindings, recall of another shell's commands, repeated startup loading,
foreign prompt/EXIT hooks and automatic archiving while another shell is open.
External prompt and fzf initialization is supplied by deterministic fixtures;
release qualification separately exercises the packaged tools. Task supplies
the private Python; util-linux `script` is required, with no host-dependent test skips. Each run uses
temporary homes and cleans up its shells on failure or interruption.

The Bash startup also conditionally loads distribution-owned Midnight
Commander and bash-completion files. Their paths differ by supported
platform, so each distribution qualification uses the actual packaged files
and exercises startup there; upstream package contents are not copied into the
repository or replaced with empty lint fixtures. Generated Python and uv
activation scripts are exercised in isolated prompt tests.

fzf key bindings use `fzf --bash` from the managed version. Old distribution
key-binding files and `~/.fzf.bash` are no longer sourced. Missing optional
integration tools are skipped; failed initialization emits a warning without
aborting startup. A plain or colored fallback prompt remains available when
Oh My Posh is absent or fails.

Ctrl+T inserts a selected file path into the Bash command line and previews
the file with the same bat/batcat/sed selection as `ff`, limited to 500 lines.
Esc cancels without replacing the command you were typing. The dotfiles set
`FZF_CTRL_T_OPTS` when loading `.bash_aliases`; private `.extras` can override
these options after startup. Ctrl+R and history synchronization are unchanged.

`gl` shows the current branch's Git history, one line per commit: short hash,
branch/tag decorations, subject, author and author date in `DD.MM.YYYY`.
Colors are automatic in a terminal and omitted when redirecting output.
An optional first number limits the commits; remaining arguments go to `git log`:

```bash
gl
gl 5
gl 5 --graph
gl 10 --all
gl 5 --author='Jan Kowalski'
```

`gc 'message'` creates a commit from staged changes. `gca` amends the last
commit with staged changes, preserving its message without opening an editor.
`gca 'message'` also replaces the message. Neither shortcut runs `git add` or
pushes. Amend changes the commit ID, so avoid it for commits other people
already use.

```bash
gc 'initial message'
gca
gca 'corrected message'
```

Tmux's `Ctrl+a c`, `Ctrl+a %` and `Ctrl+a "` create a window or split in the
active local pane's current directory. This does not discover a remote SSH
session's directory. `validate:tmux` exercises all three actual key bindings,
including a directory containing spaces and quotes, as well as config reload
and the eye timer.

`~/.extras` is an optional private input outside repository static analysis.
It is loaded only when present; a load failure emits a warning without aborting
startup. Its contents remain the user's responsibility.

Workflow validation runs locally without GitHub credentials. Set `GH_TOKEN`,
`GITHUB_TOKEN` or use an active `gh` login to additionally enable Zizmor's
online audits. The GitHub Actions workflow supplies its repository token.
