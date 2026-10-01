# Tool updates and rollback

Use this runbook to test a new version before changing the normal setup. Every
candidate needs an exact version, a SHA-256 digest from the upstream release,
and the same checks used for a normal installation. Keep the current and the
candidate installations until rollback has been tested.

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

Edit only the intended pins in `candidate/versions.env` or
`candidate/dotfiles-release.env`. For a daily tool, install the current selection
first, record its version and canonical link, then run the candidate from the
other read-only checkout. This tested example uses Debian 13 and an immutable
image digest. Replace `TOOL` and the version check for another daily tool:

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

For a restricted candidate, prepare the exact upstream file in the layout
documented in [SETUP.md](SETUP.md), mount it read-only, add `--network none`,
and use a separate empty home:

```bash
docker run --rm --network none \
  --tmpfs /home/candidate:exec,uid=1000,gid=1000 \
  --mount "type=bind,src=$candidate_root/candidate,dst=/src,readonly" \
  --mount "type=bind,src=$HOME/tool-archives,dst=/archives,readonly" \
  "$image" sh -euxc '
    useradd --uid 1000 --home-dir /home/candidate candidate
    chown candidate:candidate /home/candidate
    su candidate -s /bin/bash -c '\''set -euo pipefail
      HOME=/home/candidate /src/setup-tools --from /archives k9s
      "$HOME/bin/k9s" version --short'\''
  '
```

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

For a persistent rollback, restore the earlier scalar version and digest in
`versions.env`, then run one of these commands from that reviewed revision:

```bash
./setup-tools k9s
./setup-tools --from "$HOME/tool-archives" k9s
```

If the retained installation is intact, neither command needs its old source
file. If it is absent, the restricted command reports the exact required path.
The same procedure applies to `gh`, `oh-my-posh`, `rg` and the complete
`nvim-VERSION` executable tree. Change `validation.env` for Task's private
validation bootstrap. A daily ShellCheck change belongs in `versions.env`;
Task validation and Mason keep their own pins.

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

The next `setup-tools k9s` selects the scalar pin again. Keep the older pin in
`versions.env` for a persistent rollback. Treat `uv` with `uvx`, and `kubectx`
with `kubens`, as paired selections.

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
git diff -- offline versions.env nvim2/.config/nvim2/lua/custom/lsp.lua
```

The generator creates an empty HOME, installs the pinned `PIP_TOOLS_VERSION`
into a venv made with the pinned standalone Python, reads fresh Mason receipts
through Neovim/Lua, and resolves against `https://pypi.org/simple`. It writes
the checked-in `.in` and hashed `.lock` files. For a preinstalled receipt tree,
set `DOTFILES_PYTHON_RECEIPTS` and `NVIM_BIN` explicitly. This is still a
connected operation unless every pip-tools and target dependency is supplied
through an explicitly complete index or `--find-links` workflow. Normal builds
do not resolve dependencies again. The target installs only the locked binary
wheels with `--no-index --require-hashes --only-binary=:all:` and runs
`pip check`; the standalone interpreter alone does not contain ansible-core,
ansible-lint or yamllint.

## Project runtime rollback

Project runtimes remain under asdf. Put the earlier version first in the
corresponding ordered list in `versions.env`, then reconcile it:

```bash
./setup-asdf terraform kubectl helm python nodejs
asdf current
```

The first version becomes the home default. A project's `.tool-versions` and
an `ASDF_<TOOL>_VERSION` environment override still take precedence. Keep all
required project versions in the list, use the asdf shims, and do not add
same-named launchers in `~/bin`. After changing Node.js or global npm tools,
run `asdf reshim nodejs VERSION` and check both `node --version` and
`npm --version`.

Direct restricted kubectl and Helm installations are the sole multi-version
case in `setup-tools`. Run a version-qualified executable temporarily, or put
the required version first and rerun the importer:

```bash
"$HOME/bin/kubectl-1.27.11" version --client
"$HOME/bin/helm-3.22.0" version --short
./setup-tools --from "$HOME/tool-archives" kubectl helm
```

To roll back asdf itself or a plugin, restore its executable version, digest
or plugin commit in `versions.env`, run `setup-asdf`, and verify every retained
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
[the offline release runbook](nvim2/.config/nvim2/offline-releases.md) for
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
