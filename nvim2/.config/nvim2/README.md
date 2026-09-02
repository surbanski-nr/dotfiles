# nvim2

`nvim2` is the minimal development Neovim profile in this dotfiles
repository. It is based on
[kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim), uses Neovim
0.12's built-in `vim.pack`, and tracks plugin revisions in
`nvim-pack-lock.json`.

## Start the profile

After stowing `nvim2`:

```bash
NVIM_APPNAME=nvim2 nvim
```

The stowed Bash configuration makes this profile the default for `nvim`,
`vim`, `vi`, `v`, `$EDITOR`, `$VISUAL` and the FZF-based `ffv` command. Use
`vold` only when the archived `~/.config/old-nvim` profile has been stowed
explicitly and is needed for reference. To start directly from this repository:

```bash
cd /home/surbanski/work/githubactions/dotfilesneovim/dotfiles/nvim2/.config/nvim2
XDG_CONFIG_HOME="$(dirname "$PWD")" NVIM_APPNAME=nvim2 nvim
```

If this profile was stowed before it moved under `.config/nvim2`, first check
the active path:

```bash
readlink -f ~/.config/nvim2/init.lua
```

The resolved path should end in `nvim2/.config/nvim2/init.lua`. If it does not,
or `bstow` reports a regular file where it needs a symlink, preserve the whole
old profile and stow a clean one:

```bash
cd ~/github.com/surbanski/dotfiles
backup="$HOME/.config/nvim2.backup-$(date -u +%Y%m%d-%H%M%S)"
mv "$HOME/.config/nvim2" "$backup"
./bstow -v -t "$HOME" stow nvim2
readlink -f ~/.config/nvim2/init.lua
```

Do not delete a conflicting regular file without inspecting it. The backup
keeps old lockfiles and settings available until the clean profile has been
verified. A broken `init.lua` symlink starts vanilla Neovim without this
profile or its commands.

When a custom module is removed from the repository, use a forced restow to
remove package-owned links that no longer have a source. The standard Kickstart
loader deliberately fails on a broken module link instead of silently starting
an incomplete profile:

```bash
cd ~/github.com/surbanski/dotfiles
./bstow -v -f -t "$HOME" restow nvim2
bash ~/.config/nvim2/tests/check.sh
```

Plugins are restored from `nvim-pack-lock.json` when Neovim starts. External
tools and Treesitter parsers are deliberately not installed in the background;
provision or synchronize their pinned versions explicitly with:

```vim
:Nvim2ToolsInstallSync
```

Then validate the complete profile from the shell:

```bash
bash ~/.config/nvim2/tests/check.sh
```

Use Neovim 0.12.4 or newer.

## Clean rebuild on a connected machine

`bstow restow nvim2` updates the configuration symlinks, but it does not remove
downloaded plugins, Mason packages, language servers, formatters, linters,
Treesitter parsers or caches. A routine update does not need to remove them.
Use this clean rebuild after a large configuration or plugin-manager change,
or when `:Nvim2Check` reports undeclared installed tools or parsers.

Close every Nvim2 process first. The following procedure moves the generated
profile aside instead of deleting it. It restores Mini Visits, Telescope
history, ShaDa marks and registers, and persistent undo files:

```bash
(
  set -euo pipefail

  data="$HOME/.local/share/nvim2"
  state="$HOME/.local/state/nvim2"
  cache="$HOME/.cache/nvim2"
  backup="$HOME/dotfiles-backup/nvim2-$(date -u +%Y%m%d-%H%M%S)"

  if [[ -L "$data" ]]; then
    printf 'Nvim2 data is a platform-release symlink; use the offline release runbook.\n' >&2
    exit 1
  fi

  mkdir -p "$backup"
  [[ ! -e "$data" ]] || mv "$data" "$backup/data"
  [[ ! -e "$state" ]] || mv "$state" "$backup/state"
  [[ ! -e "$cache" ]] || mv "$cache" "$backup/cache"

  mkdir -p "$data" "$state"
  for file in mini-visits-index telescope_history; do
    [[ ! -f "$backup/data/$file" ]] || cp -a "$backup/data/$file" "$data/"
  done
  for directory in shada undo; do
    [[ ! -d "$backup/state/$directory" ]] || cp -a "$backup/state/$directory" "$state/"
  done

  printf 'Previous generated profile: %s\n' "$backup"
)

cd "$HOME/github.com/surbanski/dotfiles"
timeout 1200s env NVIM_APPNAME=nvim2 \
  nvim --headless '+Nvim2ToolsInstallSync' '+qa!'
timeout 120s bash "$HOME/.config/nvim2/tests/check.sh"
```

The first Nvim2 startup restores only plugins declared in the current config at
revisions from `nvim-pack-lock.json`. `Nvim2ToolsInstallSync` then installs the
pinned Mason tools and declared Treesitter parsers. Keep the backup until the
checks and normal editing work. Do not use this procedure for an offline
platform release, where `~/.local/share/nvim2` is an activation symlink; use the
[offline release runbook](offline-releases.md) instead.

Legacy profiles use separate application directories and do not affect Nvim2.
If neither plain `nvim` nor `vold` is needed anymore, inspect and archive their
old downloads and caches separately:

```bash
find "$HOME/.local/share" "$HOME/.local/state" "$HOME/.cache" \
  -maxdepth 1 \( -name nvim -o -name old-nvim \) -print
```

Do not remove a listed directory until its corresponding profile is no longer
needed.

## Transfer to a machine without internet access

Nvim2 is deployed as a versioned platform release containing Neovim, Node.js,
ripgrep, the exact dotfiles commit, locked plugins, pinned Mason tools,
compiled Treesitter parsers, parser revision metadata and queries. Build a
separate release for each exact target platform and architecture. Use a
connected Debian or Ubuntu host to run separate Ubuntu 24.04, Ubuntu 26.04 and
Amazon Linux 2023 builder containers.

The complete connected-builder, offline-installation, upgrade, activation and
rollback runbook is in
[Nvim2 offline releases](offline-releases.md). It also
explains the three-artifact matrix and why releases must be built from an empty
data directory.

Do not copy a developer's existing `~/.local/share/nvim2`, run update commands
on the restricted machine, or extract a new archive over the active release.
The platform runbook keeps releases in versioned directories and switches the
canonical data and Neovim symlinks, making rollback a symlink and Git commit
change.

## Plugin and configuration maintenance

The commands below review individual changes on a connected trusted machine.
After they pass, deploy them by building a complete
[Nvim2 offline release](offline-releases.md) for every
target OS and architecture. Plugins, Mason tools, language servers, formatters,
linters, parsers and Neovim itself are released and rolled back as one tested
unit.

| Action                                                | Command                                               |
| ----------------------------------------------------- | ----------------------------------------------------- |
| Inspect installed plugin state without network access | `:lua vim.print(vim.pack.get(nil, { info = false }))` |
| Fetch and review plugin updates                       | `:lua vim.pack.update()`                              |
| Fetch and review one plugin                           | `:lua vim.pack.update({ 'PLUGIN' })`                  |
| Apply proposed plugin updates                         | `:write` in the update window                         |
| Cancel proposed plugin updates                        | `:quit` in the update window                          |
| Check locked plugins, tools, parsers and hardening    | `:Nvim2Check`                                         |
| Run smoke tests and startup benchmark                 | `bash ~/.config/nvim2/tests/check.sh`                 |
| Check profile health                                  | `:checkhealth kickstart`                              |
| Check LSP health                                      | `:checkhealth vim.lsp`                                |
| Check Treesitter health                               | `:checkhealth nvim-treesitter`                        |

### Validate the profile

`:Nvim2Check` opens a normal Neovim health report for the custom profile. It
checks Neovim 0.12.4 or newer, plugin revisions against
`nvim-pack-lock.json`, disabled plugin build hooks, exact Mason and Treesitter
inventories, Mason launchers and representative executable version commands.
It does not install or update anything.

Run the stronger headless check after provisioning a VM and after accepting
plugin, Mason or parser updates:

```bash
bash ~/.config/nvim2/tests/check.sh
```

From this repository's Nvim2 configuration directory, the equivalent command
is `bash tests/check.sh`. The script exits nonzero when a smoke check fails. It
also exercises daily behavior such as register-preserving edits, snippets,
hidden-file search, Treesitter folds, Mermaid preview and formatting controls.

The script performs five isolated headless starts and reports the minimum,
median and maximum startup time. Startup speed depends on the VM, filesystem
and cache, so there is no shared default failure limit. After measuring a
healthy machine, enforce a local median limit when checking future updates:

```bash
NVIM2_MAX_STARTUP_MS=200 bash ~/.config/nvim2/tests/check.sh
```

Change `200` to a suitable value for that machine. Use
`NVIM2_BENCHMARK_RUNS=9` for a steadier measurement or preserve the last raw
profile for inspection:

```bash
NVIM2_STARTUP_LOG=/tmp/nvim2-startup.log \
  bash ~/.config/nvim2/tests/check.sh
```

Before running `:Nvim2ToolsInstallSync`, use `NVIM2_CHECK_TOOLS=0` to skip only
the Mason-package and parser-presence checks. All plugin and custom behavior
checks still run.

### Update plugins and refresh the lockfile

`nvim-pack-lock.json` is the plugin lockfile. Do not edit it by hand. Applying
an update with `:write` changes the checked-out plugin revisions and rewrites
the lockfile automatically.

Perform updates on a connected trusted machine:

1. Make sure the dotfiles repository has no unrelated changes, then start
   Nvim2 from the shell with `NVIM_APPNAME=nvim2 nvim`.
2. After Nvim2 opens, run `:lua vim.pack.update()`. This command itself fetches
   updates and opens the built-in confirmation buffer. There is no separate
   `:PackUpdate` command. To update only one plugin, use
   `:lua vim.pack.update({ 'gitsigns.nvim' })` with its lockfile name.
3. Review every old and proposed commit in the update window. `[[` and `]]`
   move between plugins; `K` shows details; `gra` offers actions such as
   skipping the plugin under the cursor.
4. Use `:write` to accept the remaining updates, or `:quit` to discard all
   pending changes. Then use `:restart` so the new plugin code is loaded.
5. Review the resulting lockfile and configuration changes:

   ```bash
   cd ~/github.com/surbanski/dotfiles
   git diff -- nvim2/.config/nvim2/nvim-pack-lock.json
   git status --short
   ```

6. Run the health checks and exercise the affected workflows before
   committing `nvim-pack-lock.json`. At minimum, run
   `bash ~/.config/nvim2/tests/check.sh`.

To return to a known revision, restore the wanted lockfile version from Git,
set that plugin's `version` temporarily to its locked `rev`, restart, and run
`vim.pack.update({ 'PLUGIN' }, { force = true })`. See `:help vim.pack` for the
full recovery procedure.

### Update Mason tools and Treesitter parsers

Mason tools do not use `nvim-pack-lock.json` and there is no separate Mason
lockfile. Their exact versions are in `lua/custom/lsp.lua`; the Treesitter
parser list is in `lua/custom/treesitter.lua`.

1. Run `:MasonUpdate` on a connected trusted machine to refresh Mason's
   registry metadata. This does not update installed tools.
2. Open `:Mason`. Put the cursor on a package and press `c` to check its
   available update, then verify the proposed release with the upstream
   project.
3. Change that package's exact `version` in `lua/custom/lsp.lua`. Keep exact
   versions; do not remove the pin.
4. Restart Neovim so the changed table is loaded, then run:

   ```vim
   :Nvim2ToolsInstallSync
   ```

   For a repeatable headless run from the stowed profile:

   ```bash
   timeout 600s env NVIM_APPNAME=nvim2 \
     nvim --headless '+Nvim2ToolsInstallSync' '+qa!'
   ```

5. Inspect `:Mason`, run `bash ~/.config/nvim2/tests/check.sh`, and test the
   relevant LSP, formatter or linter. Commit the changed custom module after
   it passes.

`Nvim2ToolsInstallSync` already runs `MasonToolsInstallSync` and then
synchronizes the configured Treesitter parsers. Do not use
`:MasonToolsUpdateSync` to choose newer versions: it does not change the pins
in `lua/custom/lsp.lua` and it does not include the parser synchronization.

Mason runs one installer at a time because the CSS, HTML and JSON entries
otherwise launch concurrent npm installs of the same underlying package.
It disables npm's audit request only during this pinned Mason install because
the request can idle until npm's five-minute network timeout. Normal project
installs and tool-version review still use npm audit.

The command installs declarations but does not remove old ones. After deleting
a tool or parser from the configuration, remove the local stale installation
before running the exact inventory check:

```vim
:MasonUninstall PACKAGE
:lua require('nvim-treesitter').uninstall({ 'LANGUAGE' }):wait(120000)
```

Clean platform builders start without either kind of stale dependency.

### Supply-chain controls

- `nvim-pack-lock.json` pins every plugin to an exact Git commit. No plugin
  update runs automatically.
- A `version` in `vim.pack.add` is an allowed update channel, not the installed
  revision. Most plugin declarations omit it intentionally and rely on the
  lockfile for exact reproducibility. blink.cmp stays on major version 1,
  Neo-tree selects released semantic-version
  tags, and Treesitter follows its `main` branch because those are deliberate
  update-channel constraints. Do not copy exact tags into every declaration:
  doing so would freeze `vim.pack.update()` at those tags.
- Mason tools are version-pinned and are installed only through
  `:Nvim2ToolsInstallSync`; opening Neovim or a new file does not download a
  missing tool or parser.
- The configuration does not execute plugin-controlled build hooks.
  `telescope-fzf-native.nvim` was removed, and snippets use Neovim's built-in
  engine without a separate native extension.
- Blink uses its Lua fuzzy matcher instead of downloading its optional native
  matcher.

When reviewing a proposed plugin commit in another terminal, use its old and
new revisions from the update window. For example:

```bash
git -C ~/.local/share/nvim2/site/pack/core/opt/PLUGIN \
  diff --stat OLD_COMMIT..NEW_COMMIT
git -C ~/.local/share/nvim2/site/pack/core/opt/PLUGIN \
  diff --submodule=log OLD_COMMIT..NEW_COMMIT
```

After accepting and testing updates, rebuild the offline archive described in
[Transfer to a machine without internet access](#transfer-to-a-machine-without-internet-access)
and move that tested snapshot to restricted VMs. Do not update plugins, tools
or parsers directly on those VMs.
