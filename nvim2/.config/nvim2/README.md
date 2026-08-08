# nvim2

`nvim2` is the minimal development Neovim profile in this dotfiles
repository. It is based on
[kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim), uses Neovim
0.12's built-in `vim.pack`, and tracks plugin revisions in
`nvim-pack-lock.json`.

The leader key is `Space`. This guide focuses on common daily tasks rather
than every Neovim command.

## Start the profile

After stowing `nvim2`:

```bash
NVIM_APPNAME=nvim2 nvim
```

The stowed Bash configuration makes this profile the default for `nvim`,
`vim`, `vi`, `v`, `$EDITOR`, `$VISUAL` and the FZF-based `ffv` command. Use
`vn` when the older `~/.config/nvim` profile is explicitly needed. To start
directly from this repository:

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

Plugins are restored from `nvim-pack-lock.json` when Neovim starts. External
tools and Treesitter parsers are deliberately not installed in the background;
provision or synchronize their pinned versions explicitly with:

```vim
:Nvim2ToolsInstallSync
```

Use current Neovim 0.12 stable or a recent nightly. Language installation and
tooling details are in
[`docs/neovim-nvchad-to-kickstart.md`](../../../docs/neovim-nvchad-to-kickstart.md).

## Transfer to a machine without internet access

An offline copy works when it is prepared on a connected Linux machine that
matches the target's architecture, Neovim version and home-directory layout.
First stow this profile on the connected machine, start it, and run:

```vim
:Nvim2ToolsInstallSync
```

After it finishes, quit Neovim and archive the installed plugins, Treesitter
parsers and Mason tools:

```bash
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
tar -C "$data_home" -czf "$HOME/nvim2-offline-$(uname -m).tar.gz" \
  nvim2/site/pack/core \
  nvim2/site/parser \
  nvim2/mason
```

Transfer that archive and this dotfiles repository to the target. Stow the
`nvim2` profile there, then extract the data archive:

```bash
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
mkdir -p "$data_home"
tar -C "$data_home" -xzf "nvim2-offline-$(uname -m).tar.gz"
NVIM_APPNAME=nvim2 nvim --headless '+checkhealth vim.lsp' '+qa!'
```

The archive contains:

- `site/pack/core`: all plugin sources managed by `vim.pack`;
- `site/parser`: the compiled Treesitter parsers;
- `mason`: language servers, formatters, linters, registries and their local
  launcher symlinks.

Do not copy `~/.cache/nvim2`; it is disposable. A leftover
`~/.local/share/nvim2/lazy` directory belongs to the older package setup and is
not used by this profile. Copy `~/.local/state/nvim2` only if saved sessions,
ShaDa history and logs are wanted too.

This is not a universal binary bundle. Mason includes native Linux binaries,
Node programs and Python virtual environments. Treesitter parsers and some
plugins are compiled. Use the same OS family, CPU architecture and Neovim
version on both machines. Neovim itself is not included: install a matching
0.12 package or transfer its complete release directory. Keep the same
absolute data path and preferably the same username because Python launchers
contain the original home path. Install runtime dependencies such as `git`,
`nodejs`, `python3`, `ripgrep` and `fd-find` from the target's package
repository. If a configured tool is added later, rebuild the archive on the
connected matching machine; do not run the installer on the isolated target
and expect missing packages to download.

## Enabled plugin set

None of these plugins is bundled with Neovim. `vim.pack` downloads every one
from its own repository. “Kickstart module” means the configuration file came
with the Kickstart template, not that the plugin comes with Neovim.

| Plugin | Configuration source | Purpose in this profile |
|---|---|---|
| `LuaSnip` | Main `init.lua` | Expand the custom global, Lua and Markdown snippets under `snippets/` |
| `blink.cmp` | Main `init.lua` | Provide completion from LSP, filesystem paths and LuaSnip |
| `conform.nvim` | Main `init.lua` | Format manually and on save, including Ruff formatting for Python |
| `fidget.nvim` | Main `init.lua` | Show language-server progress without a permanent UI panel |
| `gitsigns.nvim` | Kickstart module | Show Git changes and provide hunk, blame and diff actions |
| `guess-indent.nvim` | Main `init.lua` | Detect indentation settings from the current file |
| `mason-lspconfig.nvim` | Main `init.lua` | Connect Mason-installed servers to Neovim's LSP configuration names |
| `mason-tool-installer.nvim` | Main `init.lua` | Install pinned servers, formatters and linters only when explicitly requested |
| `mason.nvim` | Main `init.lua` | Provide the external-tool registry, installer and `:Mason` interface |
| `mini.nvim` | Main `init.lua` | Supply text objects, surroundings, alignment, split/join, visited files, statusline, icons and buffer removal |
| `neo-tree.nvim` | Kickstart module | Provide the sidebar filesystem browser and file operations |
| `nvim-highlight-colors` | Custom module | Preview color values inline on demand; lazy-loaded by `<leader>tc` |
| `nvim-lint` | Kickstart module | Publish Hadolint, TFLint and yamllint results as diagnostics |
| `nvim-lspconfig` | Main `init.lua` | Supply default commands, filetypes and root detection for language servers |
| `nvim-treesitter` | Main `init.lua` | Install parsers and queries used by Neovim's built-in Treesitter runtime |
| `nui.nvim` | Neo-tree dependency | Supply popup and layout components required by Neo-tree |
| `plenary.nvim` | Telescope and Neo-tree dependency | Supply shared Lua utilities required by those plugins |
| `render-markdown.nvim` | Custom module | Render Markdown headings, lists, tables and code blocks inside Neovim |
| `telescope-ui-select.nvim` | Main `init.lua` | Display `vim.ui.select` choices in a Telescope dropdown |
| `telescope.nvim` | Main `init.lua` | Search files, text, buffers, commands, symbols and diagnostics |
| `todo-comments.nvim` | Main `init.lua` | Highlight and search TODO-style comments |
| `which-key.nvim` | Main `init.lua` | Show available mappings after a key prefix |

Neovim itself supplies `vim.pack`, the LSP client, the Treesitter runtime,
diagnostic APIs, netrw and the default colorscheme. In particular,
`nvim-lspconfig` and `nvim-treesitter` are external plugins despite their
names.

The user-selected additions are under `lua/custom/plugins/`. Each plugin file
owns both its `vim.pack.add` declaration and its setup; `init.lua` explicitly
loads the enabled files. Persistence remains there with its `require` commented
out. Core setup remains in the numbered sections of the main `init.lua`;
bundled Kickstart modules such as Gitsigns, linting and Neo-tree are under
`lua/kickstart/plugins/`.

Plugins with direct actions have workflows in the sections below. Some work
automatically or only support another plugin, so they do not need a daily key
sequence:

| Plugin | Day-to-day behavior |
|---|---|
| `guess-indent.nvim` | Detects indentation when a buffer opens; use `:GuessIndent` to run it again and `:setlocal shiftwidth? tabstop? expandtab?` to inspect the result |
| `fidget.nvim` | Shows LSP progress in a temporary notification; use `:Fidget history` to inspect earlier messages |
| `mason-lspconfig.nvim`, `mason-tool-installer.nvim`, `nvim-lspconfig` | Connect configured language servers; inspect them with `:Mason` and install pinned versions with `:Nvim2ToolsInstallSync` |
| `nvim-treesitter` | Supplies parsing, highlighting, indentation and injections automatically for installed languages |
| `nvim-lint` | Runs configured linters after save and publishes their results through the diagnostic workflow below |
| `nui.nvim`, `plenary.nvim` | Runtime libraries for Neo-tree and Telescope; there is nothing to invoke directly |
| `telescope-ui-select.nvim` | Shows `vim.ui.select` prompts, including Mini Visits choices, in a Telescope dropdown |

The active colorscheme is Neovim's built-in `default` with its dark
`NvimDark*` palette. The custom Isekai colorscheme and palette remain under
`colors/isekai.lua` and `lua/palette.lua` but are not loaded.

### Switch the colorscheme

To try Isekai for the current Neovim session:

```vim
:colorscheme isekai
```

Return to Neovim's default dark palette with:

```vim
:colorscheme default
```

Nvim2 captures the startup `default` highlights after its plugins are
configured. Returning from Isekai therefore restores the same white-and-green
appearance seen at startup, including Telescope and Markdown groups, and
clears Isekai's terminal palette.

For a persistent change, edit the colorscheme line in `init.lua`. Use this for
Isekai:

```lua
vim.cmd.colorscheme 'isekai'
```

Use this to switch back to the Neovim default:

```lua
vim.cmd.colorscheme 'default'
```

Restart Neovim after editing the file, or run `:source $MYVIMRC`. Isekai keeps
syntax groups such as methods, functions, delimiters, docstrings and return
keywords unbolded; Markdown strong text and headings remain bold by design.

## Discover mappings inside Neovim

These are the fastest ways to find a mapping when this README is outdated or
incomplete:

| Action | Command |
|---|---|
| Show the next available leader keys | Press `Space` and wait for which-key |
| Search configured mappings | `<leader>sk` |
| Inspect a normal-mode mapping | `:verbose nmap <keys>` |
| Inspect an insert-mode mapping | `:verbose imap <keys>` |
| Read help for a key | `:help <keys>` |
| List commands | `<leader>sc` |

Notation used below:

- `<leader>` means `Space`.
- `<C-x>` means `Ctrl+x`.
- `<S-x>` means `Shift+x`.
- `<A-x>` means `Alt+x`.
- Normal mode is the default mode reached with `Esc`.

## Daily Neovim basics

### Files and commands

| Action | Keys or command |
|---|---|
| Open a file | `:edit path/to/file` |
| Save current file | `:write` or `:w` |
| Save all changed files | `:wall` or `:wa` |
| Save and quit | `:wq` |
| Quit current window | `:quit` or `:q` |
| Quit without saving | `:q!` |
| Quit Neovim | `:qa` |
| Repeat the last command-line command | `@:` |
| Repeat the last normal-mode change | `.` |
| Open path or URL under cursor | `gx` |
| Open built-in directory browser | `:Explore` |
| Open directory browser on the left | `:Lexplore` |

`netrw` supplies `:Explore`. Neo-tree is the enabled sidebar browser; press
`\` to reveal the current file or focus the tree.

### Movement and search

| Action | Keys |
|---|---|
| Move left, down, up, right | `h`, `j`, `k`, `l` |
| Next or previous word | `w`, `b` |
| End of word | `e` |
| Start, first text, or end of line | `0`, `^`, `$` |
| First or last line | `gg`, `G` |
| Jump to a line | `<line>G`, for example `42G` |
| Previous or next paragraph/block | `{`, `}` |
| Matching bracket | `%` |
| Half-page down or up | `<C-d>`, `<C-u>` |
| Center current line | `zz` |
| Find character forward | `f<char>` |
| Move before character forward | `t<char>` |
| Repeat or reverse character search | `;`, `,` |
| Search forward or backward | `/text`, `?text` |
| Next or previous search match | `n`, `N` |
| Search word under cursor | `*` forward, `#` backward |
| Clear search highlighting | `<Esc>` |
| Jump back or forward in jump list | `<C-o>`, `<C-i>` |

### Editing, selection, undo and registers

| Action | Keys |
|---|---|
| Insert before or after cursor | `i`, `a` |
| Insert at start or end of line | `I`, `A` |
| Open line below or above | `o`, `O` |
| Delete character | `x` |
| Delete line without changing registers | `dd` |
| Delete inside word | `diw` |
| Change inside word | `ciw` |
| Yank line | `yy` |
| Yank inside word | `yiw` |
| Paste after or before cursor | `p`, `P` |
| Undo or redo | `u`, `<C-r>` |
| Character, line, or block selection | `v`, `V`, `<C-v>` |
| Reselect last visual selection | `gv` |
| Indent or unindent selection | `>`, `<` |
| Join current line with next | `J` |
| Toggle boolean-like value under cursor | `<leader>tv` |
| Add an empty line below or above | `]<Space>`, `[<Space>` |
| Show registers | `:registers` |
| Paste latest explicit yank | `"0p` |
| Paste from numbered yank ring | `"1p` through `"9p` |
| Delete with another motion without changing registers | `"_d{motion}`, for example `"_diw` |
| Delete a selection without changing any register | Select text, then `"_d` |
| Yank into and paste from named register `a` | `"ay{motion}`, then `"ap` |
| Use system clipboard explicitly | `"+y`, `"+p` |

Registers are small text storage slots. The `"{register}` prefix selects a
register for the next operation:

- `"` is the unnamed register used by plain `y`, most `d` operations, `p` and
  `P`. The mapped `dd` is an exception.
- `0` keeps the latest explicit yank, even after a later normal delete. Use
  `"0p` when plain `p` would paste recently deleted text instead.
- `1` through `9` form this profile's small yank history: `"1p` pastes the
  newest saved yank, `"2p` the previous one, and so on. Normal deletes can
  still alter these numbered registers.
- `a` through `z` are manual named registers. For example, `"ayy` stores a
  line in `a`, `"ap` pastes it, and `"Ayy` appends another line to it.
- `_` is the black-hole register. Text sent there is discarded. This profile
  maps `dd` to it automatically; use explicit `"_diw` or visual `"_d` for
  other deletions that should not replace text waiting to be pasted.

Use `:registers 0 1 2 3 4 5 6 7 8 9` to inspect the yank history, or
`:registers` to inspect every register.

This profile changes register behavior:

- `dd`, `c`, `C`, `cc`, and visual `c` use the black-hole register, so these
  operations do not overwrite the latest yank.
- Visual `p` preserves the latest yank instead of replacing it with the
  selected text.
- Successful yanks are copied into registers `1` through `9` as a small yank
  ring.
- `clipboard=unnamedplus` is enabled, so normal yanks and pastes also use the
  system clipboard when a clipboard provider is available.

`<leader>tv` replaces the complete value under the cursor without changing a
register. It handles matching case variants of `true`/`false`, `yes`/`no` and
`on`/`off`, plus lowercase `enable`/`disable` and `enabled`/`disabled`. Unknown
words are left unchanged.

### Comments, spell checking and folds

These are Neovim mappings, not separate plugins.

| Action | Keys |
|---|---|
| Toggle comment on current line | `gcc` |
| Toggle comment over a motion | `gc<motion>`, for example `gcap` |
| Toggle comment on selection | Select text, then `gc` |
| Next or previous misspelling | `]s`, `[s` |
| Suggest spelling corrections | `z=` |
| Add word to dictionary | `zg` |
| Mark word as incorrect | `zw` |
| Toggle fold | `za` |
| Open or close fold | `zo`, `zc` |
| Open or close all folds | `zR`, `zM` |
| Move to next or previous fold | `zj`, `zk` |

Spell checking is enabled automatically for Markdown, text, and Git commit
buffers. Supported filetypes use Neovim's native Treesitter fold expression;
folds start open and the normal `z` mappings above control them. Files without
an installed parser retain marker folds (`{{{` and `}}}`). Missing parsers are
installed only by `:Nvim2ToolsInstallSync`, never while opening a file.

## Buffers, windows and terminal mode

### Buffers

| Action | Keys or command |
|---|---|
| Pick an open buffer | `<leader><leader>` |
| Remove current buffer without breaking the layout | `<C-x>` |
| List buffers | `:ls` |
| Next or previous buffer | `]b`, `[b` or `:bnext`, `:bprevious` |
| Switch by buffer number or name | `:buffer <number-or-name>` |
| Delete current buffer | `:bdelete` |

`<C-x>` normally decrements a number in stock Neovim. This profile replaces
it with Mini buffer removal.

### Windows and splits

| Action | Keys or command |
|---|---|
| Horizontal split | `:split` or `<C-w>s` |
| Vertical split | `:vsplit` or `<C-w>v` |
| Focus left, down, up, right split | `<C-h>`, `<C-j>`, `<C-k>`, `<C-l>` |
| Close current split | `<C-w>c` |
| Keep only current split | `<C-w>o` |
| Make splits equal size | `<C-w>=` |
| Move split to far left, bottom, top, right | `<C-w>H`, `<C-w>J`, `<C-w>K`, `<C-w>L` |

Splits are automatically resized evenly when the terminal size changes.

### Terminal mode and terminal clipboard

| Action | Keys |
|---|---|
| Open a terminal buffer | `:terminal` |
| Leave terminal input mode | `<Esc><Esc>` |
| Copy terminal selection | `Ctrl+Shift+C` |
| Paste in terminal | `Ctrl+Shift+V` |

Mouse handling is disabled in Neovim so terminal selection stays under the
terminal emulator's control. Direct SSH sessions use OSC 52 for clipboard
copying. Tmux can block OSC 52 because its configuration currently uses
`set-clipboard off`.

## Search and Telescope

| Action | Keys |
|---|---|
| Find files | `<leader>sf` |
| Live grep project text | `<leader>sg` |
| Find files in nearest Git repository | `<leader>sF` |
| Live grep nearest Git repository | `<leader>sG` |
| Search word under cursor or visual selection | `<leader>sw` |
| Search current buffer | `<leader>/` |
| Search text only in open files | `<leader>s/` |
| Search open buffers | `<leader><leader>` |
| Recent files | `<leader>s.` |
| Search diagnostics | `<leader>sd` |
| Search help | `<leader>sh` |
| Search mappings | `<leader>sk` |
| Search commands | `<leader>sc` |
| List Telescope pickers | `<leader>ss` |
| Resume last picker | `<leader>sr` |
| Search this Neovim configuration | `<leader>sn` |

Common keys inside a Telescope picker:

| Action | Insert mode | Normal mode |
|---|---|---|
| Move to next or previous result | `<C-n>`, `<C-p>` | `j`, `k` |
| Open result | `<CR>` | `<CR>` |
| Open in horizontal split | `<C-x>` | `<C-x>` |
| Open in vertical split | `<C-v>` | `<C-v>` |
| Open in a tab | `<C-t>` | `<C-t>` |
| Scroll preview | `<C-d>`, `<C-u>` | `<C-d>`, `<C-u>` |
| Close picker | `<Esc>` | `q` |
| Show picker mappings | `<C-/>` | `?` |

`<leader>/` searches only the current buffer, so it never searches an entire
workspace. `<leader>sf`, `<leader>sg` and `<leader>sw` use the current working
directory shown by `:pwd`. `<leader>sF` and `<leader>sG` walk upward from the
current file to the nearest `.git` directory and search only that repository;
they fall back to `:pwd` outside Git. This is useful when one Neovim workspace
contains several repositories.

Scope file or text search to any other repository or subdirectory without
changing the working directory:

```vim
:Telescope find_files cwd=repo-a
:Telescope live_grep cwd=repo-a
```

Paths can be absolute or relative to `:pwd`. Alternatively, use
`:tcd path/to/repo` to give the current tab its own working directory; the
regular Telescope mappings in that tab will then search that repository.
`:lcd` does the same for only the current window, while `:cd` changes the
working directory globally.

One Neovim process over several repositories is valid, especially for
cross-repository changes. LSP and Gitsigns determine roots per buffer, while
Telescope uses the current working directory. A useful compromise is one tab
and `:tcd` per active repository. Use separate Neovim processes when the
repositories need independent working directories or tool state.

## Quickfix list

Quickfix is a project-wide list of file locations. Common ways to populate it
in this profile are Telescope searches, Gitsigns (`<leader>hq` or
`<leader>hQ`) and `:TodoQuickFix`.

Inside any Telescope picker:

| Action | Keys |
|---|---|
| Replace quickfix with all currently filtered results and open it | `<C-q>` |
| Mark or unmark individual results | `<Tab>`, `<S-Tab>` |
| Replace quickfix with only the marked results and open it | `<M-q>` (Alt-q) |

Both Telescope actions replace the current quickfix list; they do not append
to it. `<M-q>` may depend on the terminal correctly sending Alt-modified keys.

Using the resulting quickfix list:

| Action | Keys or command |
|---|---|
| Open or close the quickfix window | `:copen`, `:cclose` |
| Open the entry under the cursor | `<CR>` |
| Open the entry in a new split | `<C-w><CR>` |
| Next or previous entry | `]q`, `[q` or `:cnext`, `:cprevious` |
| Last or first entry | `]Q`, `[Q` or `:clast`, `:cfirst` |
| Remove the entry under the cursor from this list | `dd` in the quickfix window |
| Run an Ex command for every entry | `:cdo {command}` |

`dd` only removes the selected location from the current quickfix list. It
does not delete a file, change source code or affect a window-local location
list. Diagnostic `<leader>q` uses a location list instead; open and close that
with `:lopen` and `:lclose`, and navigate it with `]l` and `[l`.

### Find and replace with review

For one buffer, confirm every replacement with:

```vim
:%s#old#new#gc
```

For a directory or repository:

1. Run `:Telescope live_grep cwd=path/to/repo` and search for `old`.
2. Press `<C-q>` to put all filtered matches in quickfix. To keep only some
   matches, mark them with `<Tab>` and press `<M-q>` instead.
3. Review entries with `]q` and `[q`; press `dd` in the quickfix window to
   remove any location that must not change.
4. Run `:cdo s#old#new#gc | update` to visit only the listed lines and confirm
   every replacement.

At each confirmation, use `y` for yes, `n` for no, `a` for all remaining, or
`q` to stop. The substitute pattern is a Vim regular expression. Prefix a
literal search with `\V`, for example `:cdo s#\Vold.name#new_name#gc | update`.

To replace without per-occurrence confirmation, use
`:cfdo %s#old#new#g | update`. `:cfdo` runs once per file represented in
quickfix and searches the complete file; `:cdo` is safer after removing
individual quickfix locations because it operates only on listed lines. The
initial Telescope `cwd` is what keeps either command inside the chosen
directory.

## LSP, diagnostics and completion

LSP mappings become useful when a configured language server attaches to the
current buffer.

### Code navigation and actions

| Action | Keys |
|---|---|
| Hover documentation | `K` |
| Go to definition with Telescope | `grd` |
| Go to declaration | `grD` |
| Find references | `grr` |
| Find implementations | `gri` |
| Go to type definition | `grt` |
| Rename symbol | `grn` |
| Code action | `gra` in normal or visual mode |
| Document symbols | `gO` |
| Workspace symbols | `gW` |
| Return from a jump | `<C-t>` |
| Toggle inlay hints when supported | `<leader>th` |
| Signature help in insert mode | `<C-s>` or `<C-k>` |
| Start and expand an LSP selection | `van` from normal mode, then repeat `an` |
| Shrink the current LSP selection | `in` while still in visual mode |

Treesitter provides syntax highlighting, indentation, injections and parser
support automatically. It has no custom daily mapping in this profile. The
`an` and `in` mappings above are Neovim 0.12 LSP selection ranges. They are not
normal-mode or leader mappings: normal-mode `a` enters insert mode. The
language server must support `textDocument/selectionRange`. Mini.ai uses `aa`
and `ii` for its next-textobject variants. Those are prefixes rather than
standalone normal-mode mappings; for example, `vaa)` selects around the next
parenthesized text and `dii)` deletes inside the next parenthesized text.

### Diagnostics

| Action | Keys |
|---|---|
| Next or previous diagnostic | `]d`, `[d` |
| Last or first diagnostic in buffer | `]D`, `[D` |
| Show diagnostic at cursor | `<C-w>d` |
| Put diagnostics in location list | `<leader>q` |
| Search diagnostics with Telescope | `<leader>sd` |
| Next or previous location-list item | `]l`, `[l` or `:lnext`, `:lprevious` |
| Next or previous quickfix item | `]q`, `[q` or `:cnext`, `:cprevious` |

The diagnostic float opens automatically after jumping with `[d` or `]d`.

### Completion and snippets

| Action | Keys |
|---|---|
| Open completion or documentation | `<C-Space>` |
| Next or previous completion item | `<C-n>`, `<C-p>` or arrows |
| Accept selected completion | `<C-y>` |
| Close completion menu | `<C-e>` |
| Toggle signature help | `<C-k>` |
| Move forward or backward through snippet fields | `<Tab>`, `<S-Tab>` |
| Expand custom snippet or choose next option | `<C-c>` |

Blink supplies completion from LSP, paths and LuaSnip. Regular snippets can be
accepted from Blink with `<C-y>` or expanded with `<C-c>` after typing their
trigger. Autosnippets expand as soon as their complete trigger is typed.

The custom snippets under `snippets/` are:

| File and type | Triggers | What they produce |
|---|---|---|
| `all.lua`, autosnippets in every filetype | `(`, `[`, `{`, `'`, `"` | Matching delimiters or quotes with the cursor between them |
| `markdown.lua`, regular | `` ` ``, `l`, `ll`, `t`, `tb`, `tb2`, `tb3`, `cn`, `ct`, `ci`, `cw`, `cc` | Inline code, links, images, tasks, one-to-three-column tables and GitHub NOTE/TIP/IMPORTANT/WARNING/CAUTION callouts |
| `markdown.lua`, autosnippets | `` ``` ``, `**`, `__`, `*_`, `~~`, `<<` | Fenced code, bold, italic, bold italic, strikethrough and angle brackets |
| `lua.lua`, regular | `l`, `ll`, `lm`, `lf`, `lff`, `lr`, `if`, `eif`, `for`, `forn`, `fori`, `w`, `f`, `fm`, `p`, `pi` | Local declarations, modules, functions, control flow, loops, `require`, `print` and `vim.inspect` templates |

These snippets are optional conveniences, not part of LSP support. `lua.lua`
is useful when editing this Neovim configuration, especially `lr`, `lm`, `lf`
and `pi`. The Markdown tables and callouts are useful when writing GitHub
documentation. The global delimiter autosnippets and Markdown formatting
autosnippets are the weakest fit for a minimal setup: they expand broadly,
have no syntax-aware checks and can be surprising when typing literal quotes
or Markdown punctuation. Keep them only if that automatic behavior is useful;
otherwise remove those autosnippet tables while retaining the smaller regular
Lua and Markdown set.

## Formatting, linting and tools

| Action | Keys or command |
|---|---|
| Format buffer or visual selection | `<leader>f` |
| Toggle format-on-save for this Neovim session | `<leader>tf` or `:FormatToggle` |
| Disable format-on-save globally | `:FormatDisable` |
| Disable format-on-save for current buffer | `:FormatDisable!` |
| Enable format-on-save globally | `:FormatEnable` |
| Enable format-on-save for current buffer | `:FormatEnable!` |
| Inspect formatter selection | `:ConformInfo` |
| Inspect external tools | `:Mason` |
| Install all managed tools and parsers synchronously | `:Nvim2ToolsInstallSync` |

Conform formats configured filetypes on save. `<leader>tf` is useful when one
Neovim process is opened for a repository that should not be reformatted. The
toggle lasts for that process and does not change repository files or settings.
Manual formatting with `<leader>f` remains available while format-on-save is
disabled. Ruff sorts imports and formats Python. `nvim-lint` runs configured
CLI linters after saving; it has no manual mapping.

Every managed Mason package has an exact version in `init.lua`.
`mason-tool-installer.nvim` has both automatic updates and startup installation
disabled. Change a version intentionally, then run `:Nvim2ToolsInstallSync` on
a connected trusted machine to synchronize Mason tools and the configured
Treesitter parsers.

## Git and Gitsigns

Gitsigns mappings are buffer-local and appear in files inside a Git working
tree.

| Action | Keys |
|---|---|
| Next or previous hunk | `]c`, `[c` |
| Stage hunk | `<leader>hs` |
| Reset hunk | `<leader>hr` |
| Stage selected lines | Select lines, then `<leader>hs` |
| Reset selected lines | Select lines, then `<leader>hr` |
| Stage whole buffer | `<leader>hS` |
| Reset whole buffer | `<leader>hR` |
| Preview hunk | `<leader>hp` |
| Preview hunk inline | `<leader>hi` |
| Blame current line | `<leader>hb` |
| Diff against index | `<leader>hd` |
| Diff against last commit | `<leader>hD` |
| Current-file hunks in quickfix | `<leader>hq` |
| Repository hunks in quickfix | `<leader>hQ` |
| Toggle current-line blame | `<leader>tb` |
| Toggle word-level diff | `<leader>tw` |
| Select current hunk | `vih` or use `ih` with an operator |

## Mini editing modules

### Text objects

Mini.ai extends normal `a` and `i` text objects and searches up to 500 lines.
Examples:

| Action | Keys |
|---|---|
| Select around parentheses | `va)` |
| Change inside quotes | `ci'` |
| Yank inside the next quote | `yiiq` |
| Go to left or right edge of an around-object | `g[<object>`, `g]<object>` |

### Surroundings

| Action | Keys |
|---|---|
| Add surroundings | `sa<motion><char>`, for example `saiw)` |
| Add surroundings to selection | Select text, then `sa<char>` |
| Delete surroundings | `sd<char>`, for example `sd'` |
| Replace surroundings | `sr<old><new>`, for example `sr)'` |
| Find surrounding to right or left | `sf<char>`, `sF<char>` |
| Highlight surrounding | `sh<char>` |

### Alignment and buffer removal

| Action | Keys |
|---|---|
| Align selected text interactively | Select text, press `ga`, then follow the prompt |
| Align with live preview | Select text, press `gA`, then follow the prompt |
| Remove current buffer | `<C-x>` |

### Split/join and visited files

| Action | Keys |
|---|---|
| Split or join arguments inside `()`, `[]` or `{}` | `gS` |
| Select frecent file from current working directory | `<leader>vv` |
| Select frecent file from all tracked directories | `<leader>vV` |
| Add a label to current file | `<leader>va` |
| Remove a label from current file | `<leader>vr` |
| Select a label, then one of its files | `<leader>vl` |

For split/join, place the cursor anywhere inside a bracketed argument list and
press `gS`; press it again to join the list. It is repeatable with `.` and also
works on a visual selection when automatic bracket detection chooses the wrong
region. It is pattern-based rather than syntax-aware, so nested or unusual
language constructs can occasionally need manual formatting.

Mini Visits records a normal file after it remains open for about one second
and ranks files using both recency and frequency. `<leader>vv` is scoped to
`:pwd`, which can include all repositories in a shared workspace;
`<leader>vV` searches the complete history. To create a small named working
set, open each important file, press `<leader>va` and give each the same label.
Later, `<leader>vl` selects that label and then a file. Visit history and labels
are persisted under the Nvim2 data directory when Neovim exits.

## Markdown, colors and TODO comments

| Action | Keys or command |
|---|---|
| Toggle Markdown rendering globally | `:RenderMarkdown toggle` |
| Toggle Markdown rendering for current buffer | `:RenderMarkdown buf_toggle` |
| Open a side-by-side rendered Markdown preview | `:RenderMarkdown preview` |
| Toggle inline color previews | `<leader>tc` |
| Search TODO comments | `:TodoTelescope` |
| Put TODO comments in quickfix | `:TodoQuickFix` |

`nvim-highlight-colors` is not loaded at startup because its scroll refreshes
can make large highlighted buffers less responsive. The first `<leader>tc`
loads it and immediately highlights the current buffer; later presses disable
or re-enable it. Its `:HighlightColors` command becomes available after that
first load.

The old TODO mappings (`]t`, `[t`, `<leader>ft`, `<leader>tq`) have not been
restored. Adding mappings requires no new plugin because
`todo-comments.nvim` is already installed. Prefer `<leader>tn` and
`<leader>tp` for TODO navigation: `[t`/`]t` and `[T`/`]T` are Neovim's
built-in tag-list mappings.

### Disabled session persistence

`persistence.nvim` is retained in `lua/custom/plugins/persistence.lua`, but its
`require` is commented out in `lua/custom/plugins/init.lua`. It is also absent
from `nvim-pack-lock.json`, so a clean VM does not download it. On a VM where
it was installed previously, remove its old package and lock entry once with
`:lua vim.pack.del { 'persistence.nvim' }`.

To restore persistence, uncomment its `require` line and restart Neovim. The
module's `vim.pack.add` call then installs it and records it in the lockfile. It
saves sessions automatically on exit and provides:

| Action | Keys |
|---|---|
| Save the current session now | `<leader>pw` |
| Restore session for current directory | `<leader>pr` |
| Select a saved session | `<leader>ps` |

Sessions are separated by working directory and, for non-default Git branches,
by branch. They are never restored automatically.

## Plugin and configuration maintenance

| Action | Command |
|---|---|
| Inspect installed plugin state without network access | `:lua vim.print(vim.pack.get(nil, { info = false }))` |
| Fetch and review plugin updates | `:lua vim.pack.update()` |
| Fetch and review one plugin | `:lua vim.pack.update({ 'PLUGIN' })` |
| Apply proposed plugin updates | `:write` in the update window |
| Cancel proposed plugin updates | `:quit` in the update window |
| Check profile health | `:checkhealth kickstart` |
| Check LSP health | `:checkhealth vim.lsp` |
| Check Treesitter health | `:checkhealth nvim-treesitter` |

### Update plugins and refresh the lockfile

`nvim-pack-lock.json` is the plugin lockfile. Do not edit it by hand. Applying
an update with `:write` changes the checked-out plugin revisions and rewrites
the lockfile automatically.

Perform updates on a connected trusted machine:

1. Make sure the dotfiles repository has no unrelated changes, then start
   Nvim2 from it.
2. Run `:lua vim.pack.update()`. To update only one plugin, use
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
   committing `nvim-pack-lock.json`.

To return to a known revision, restore the wanted lockfile version from Git,
set that plugin's `version` temporarily to its locked `rev`, restart, and run
`vim.pack.update({ 'PLUGIN' }, { force = true })`. See `:help vim.pack` for the
full recovery procedure.

### Update Mason tools and Treesitter parsers

Mason tools do not use `nvim-pack-lock.json` and there is no separate Mason
lockfile. Their exact versions and the Treesitter parser list are the
`ensure_installed` and `parsers` tables in `init.lua`.

1. Run `:MasonUpdate` on a connected trusted machine to refresh Mason's
   registry metadata. This does not update installed tools.
2. Open `:Mason`. Put the cursor on a package and press `c` to check its
   available update, then verify the proposed release with the upstream
   project.
3. Change that package's exact `version` in the `ensure_installed` table in
   `init.lua`. Keep exact versions; do not remove the pin.
4. Restart Neovim so the changed table is loaded, then run:

   ```vim
   :Nvim2ToolsInstallSync
   ```

   For a repeatable headless run from the stowed profile:

   ```bash
   timeout 600s env NVIM_APPNAME=nvim2 \
     nvim --headless '+Nvim2ToolsInstallSync' '+qa!'
   ```

5. Inspect `:Mason`, run the health checks, and test the relevant LSP,
   formatter or linter. Commit the changed `init.lua` after it passes.

`Nvim2ToolsInstallSync` already runs `MasonToolsInstallSync` and then
synchronizes the configured Treesitter parsers. Do not use
`:MasonToolsUpdateSync` to choose newer versions: it does not change the pins
in `init.lua` and it does not include the parser synchronization.

### Supply-chain controls

- `nvim-pack-lock.json` pins every plugin to an exact Git commit. No plugin
  update runs automatically.
- Mason tools are version-pinned and are installed only through
  `:Nvim2ToolsInstallSync`; opening Neovim or a new file does not download a
  missing tool or parser.
- The configuration does not execute plugin-controlled build hooks.
  `telescope-fzf-native.nvim` was removed and LuaSnip's optional `jsregexp`
  binary is not built because the local snippets do not use regex transforms.
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

## Bundled optional modules

Files under `lua/kickstart/plugins/` are configuration examples, not proof
that their plugins are installed. The bottom of `init.lua` decides which
modules are enabled.

| Module | State | What it adds |
|---|---|---|
| `gitsigns.lua` | Enabled | Git signs, hunk actions and mappings listed above |
| `lint.lua` | Enabled | Hadolint, TFLint and yamllint integration after save |
| `neo-tree.lua` | Enabled | Sidebar file tree and file-management actions |
| `debug.lua` | Disabled | DAP UI and Go debugging |
| `autopairs.lua` | Disabled | Automatic closing pairs while typing |
| `indent_line.lua` | Disabled | Indentation guides |

A disabled module's `vim.pack.add` call is not executed. Its plugin must also
be absent from `nvim-pack-lock.json`, because a clean `vim.pack` setup installs
every lockfile entry. Debug, autopairs, indentation guides and persistence are
currently absent from the lockfile.

The visible `>` before tab-indented lines and `·` after trailing spaces are
Neovim's built-in `listchars`, not indentation guides. Hide them temporarily
with `:set nolist` and restore them with `:set list`. Neo-tree draws separate
hierarchy lines only inside its sidebar; `guess-indent.nvim` detects indentation
settings but draws no guides.

To enable a disabled module, uncomment its `require` line near the bottom of
`init.lua` and restart Neovim. Neo-tree is enabled; its common daily keys are:

| Action in Neo-tree | Keys |
|---|---|
| Reveal current file or focus tree | `\` |
| Open file or expand directory | `<CR>` or `<Space>` |
| Preview file | `P` |
| Open in horizontal split, vertical split or tab | `S`, `s`, `t` |
| Close directory or all directories | `C`, `z` |
| Toggle hidden, dot and Git-ignored items | `H` |
| Fuzzy-find an item or directory | `/`, `D` |
| Apply a persistent name filter | `f`, type the filter, then `<CR>` |
| Clear the active filter | `<C-x>` |
| Use selected directory as root or go to its parent | `.`, `<BS>` |
| Add file or directory | `a`, `A` |
| Rename, move, copy or delete | `r`, `m`, `c`, `d` |
| Mark for copy or move | `y`, `x` |
| Paste marked items into selected directory | `p` |
| Clear marked items | `<C-r>` |
| Refresh | `R` |
| Close tree | `\` or `q` |
| Show Neo-tree's authoritative mapping help | `?` |

Usual file-management flow:

1. Press `\`, then select the parent directory with `j` and `k`.
2. Press `a` to create a file or `A` to create a directory, enter its name,
   then press `<CR>`. With `a`, a name ending in `/` also creates a directory.
3. To rename an item, select it, press `r`, edit the name and press `<CR>`.
4. To move or copy an item directly, press `m` or `c`, enter its destination
   path and press `<CR>`.
5. To move or copy through the tree, mark an item with `x` or `y`, select the
   destination directory and press `p`.
6. To remove an item, select it, press `d` and confirm the prompt.

Press `H` when a dotfile or Git-ignored item is missing. Use `/` for a quick
fuzzy jump, or `f` when the tree should stay narrowed until `<C-x>` clears the
filter. Neo-tree refreshes after file operations. Press `?` inside the tree if
a less common action or current mapping is needed.

If the debug module is enabled, it configures:

| Debug action | Keys |
|---|---|
| Start or continue | `<F5>` |
| Step into, over, or out | `<F1>`, `<F2>`, `<F3>` |
| Toggle breakpoint | `<leader>b` |
| Set conditional breakpoint | `<leader>B` |
| Toggle DAP UI | `<F7>` |

The bundled debug example is Go-focused and is not part of the current
language scope.

## Previous `nvim` plugin comparison

The previous profile imports `NvChad/NvChad` v2.5 and contains 48 files under
`nvim/.config/nvim/lua/plugins/`: 44 contain active plugin configuration and
four are fully commented-out experiments. The tables below compare those
active configurations with `nvim2`.

### Kept, replaced or partly covered

| Previous plugin | Status in `nvim2` | Difference that remains |
|---|---|---|
| `hrsh7th/nvim-cmp` | Replaced by `blink.cmp` | Different completion UI and keys; Blink is enabled by default, but its current sources omit buffer-word and Copilot completion |
| `numToStr/Comment.nvim` and `nvim-ts-context-commentstring` | Replaced by Neovim's `gc` and Treesitter-aware comment support | No meaningful daily feature is missing |
| `stevearc/conform.nvim` | Kept | New profile has broader format-on-save rules and uses Ruff for Python |
| `gbprod/cutlass.nvim` | Partly replaced by black-hole change and `dd` mappings | Other deletes can still alter delete registers; use `"_d` when that matters |
| `lewis6991/gitsigns.nvim` | Kept | New profile has more hunk, diff and blame mappings |
| `lukas-reineke/headlines.nvim` | Replaced by `render-markdown.nvim` | Browser rendering is still separate from in-editor rendering |
| `mfussenegger/nvim-lint` | Kept | Linter set is limited to the selected development languages |
| `neovim/nvim-lspconfig` | Kept | Uses the Neovim 0.12 API and the selected server list |
| `mason-org/mason.nvim` | Kept | Mason LSP and tool installers now manage the complete selected tool set |
| `olimorris/persisted.nvim` | Optional replacement retained but disabled as `folke/persistence.nvim` | If enabled, session picker mappings are `<leader>pr` and `<leader>ps` |
| `kylechui/nvim-surround` | Replaced by `mini.surround` | Surrounding keys use Mini's `sa`, `sd` and `sr` grammar |
| `nvim-telescope/telescope.nvim` | Kept | Search mappings moved from `<leader>f...` to `<leader>s...`; the old override included hidden files and custom ignore patterns while the current profile uses Telescope defaults |
| `folke/todo-comments.nvim` | Kept | Old TODO navigation/search mappings are not configured and gutter signs are disabled |
| `nvim-treesitter/nvim-treesitter` | Kept | Parsers are deliberately limited to selected languages |
| `pearofducks/ansible-vim` | Replaced by Ansible filetype detection, parser and LSP | Some legacy Vim-specific Ansible syntax behavior may differ |
| `towolf/vim-helm` | Replaced by Helm filetype detection, parser and LSP | No separate Vimscript Helm syntax plugin |
| `gbprod/yanky.nvim` | Partly replaced by registers `1` through `9` and preserved visual paste | No 50-item history, Telescope yank picker, or `[y` and `]y` history cycling |

### Active old features that are genuinely missing

| Previous plugin | What it provided | Minimal recommendation |
|---|---|---|
| `okuuva/auto-save.nvim` | Saved automatically after text changes or leaving insert mode | Do not add initially; explicit saves make format/lint timing predictable |
| `kevinhwang91/nvim-bqf` | Quickfix previews, filtering and split-opening helpers | Keep built-in quickfix until it becomes painful |
| `zbirenbaum/copilot.lua`, `copilot-cmp`, `copilot-status.nvim` | Inline AI suggestions, completion integration and status | Add only `copilot.lua` if AI completion is intentionally wanted; skip the integration/status extras |
| `folke/flash.nvim` | Label-based jumps and Treesitter-aware selection | Native `/`, `f`, `t`, LSP selection and Telescope are enough for now |
| `ray-x/go.nvim` and `guihua.lua` | Go commands, test/code helpers and tool installation | Do not add unless Go returns to the supported language list; prefer a small `gopls` setup first |
| `rmagatti/goto-preview` | Definitions, references and implementations in floating previews | Current Telescope LSP pickers cover navigation; add only if floating previews are missed |
| `ThePrimeagen/harpoon` | Persistent short list of frequently used files | Replaced for now by Mini Visits frecency and labels under `<leader>v` |
| `tzachar/highlight-undo.nvim` | Briefly highlighted text affected by undo and redo | Cosmetic; do not add |
| `kevinhwang91/nvim-hlslens` | Search match counts and search markers integrated with scrollbar | Neovim search count and normal `n`/`N` are sufficient |
| `iamcco/markdown-preview.nvim` | Browser-based Markdown preview | Add only when browser-accurate rendering is needed; current render-markdown is in-editor |
| `karb94/neoscroll.nvim` | Animated smooth scrolling | Cosmetic; do not add |
| `shortcuts/no-neck-pain.nvim` | Centered editing column with side padding | Cosmetic; use splits when focus space is needed |
| `nacro90/numb.nvim` | Previewed a target line while entering `:<line>` | Small convenience; do not add initially |
| `epwalsh/pomo.nvim` and `nvim-notify` | Pomodoro timers and notifications | Keep time management outside the editor |
| `tris203/precognition.nvim` | On-screen hints for available Vim motions | Useful while learning, but not part of a stable daily setup |
| `ahmedkhalf/project.nvim` | Project-root detection and Telescope project switching | `<leader>sF` and `<leader>sG` search the nearest Git root without another plugin |
| `petertriho/nvim-scrollbar` | Scrollbar with diagnostic and search markers | Cosmetic; signs, diagnostics and Telescope already expose this information |
| `utilyre/sentiment.nvim` | Enhanced matching-pair highlighting | Built-in match highlighting is enough |
| `nvim-pack/nvim-spectre` | Interactive project-wide search and replace | Consider only if project-wide replacements are frequent; otherwise use quickfix plus `:cdo` |
| `cshuaimin/ssr.nvim` | Treesitter structural search and replace | Add only for recurring AST-aware refactors |
| `nguyenvukhang/nvim-toggler` | Toggled values such as `true`/`false` or `on`/`off` | Replaced by the local `<leader>tv` implementation |
| `nvim-tree/nvim-tree.lua` | Persistent sidebar file explorer | Replaced by the enabled Neo-tree module |
| `Wansmer/treesj` | Split or joined syntax nodes with `gj` | Replaced for now by the enabled `mini.splitjoin`; reconsider only if syntax-aware splitting is needed |
| `folke/trouble.nvim` | Dedicated diagnostics, references and quickfix-style panels | Telescope diagnostics and location lists cover the common workflow |
| `kevinhwang91/nvim-ufo` and `promise-async` | Treesitter/indent folds and fold previews | Native Treesitter folds are enabled; only fold previews remain missing |
| `szw/vim-maximizer` | Toggled the current split between normal and maximized size | Use built-in window sizing commands such as `<C-w>_` and `<C-w>=`, or add a small mapping later |
| `sustech-data/wildfire.nvim` | Repeatedly expanded visual selection to surrounding objects | First try `van` from normal mode, then repeat `an` to expand or use `in` to shrink; this requires an LSP with selection-range support, so Wildfire can still help when language-independent expansion is needed |

### NvChad platform features no longer present

The old profile inherited these through `NvChad/NvChad`, rather than through
individual files in `lua/plugins/`:

| NvChad component | What is different now |
|---|---|
| `nvchad/base46` | Replaced by the local Isekai colorscheme and palette |
| `nvchad/ui` | Mini statusline remains, but there is no NvChad dashboard or buffer tabline |
| `nvzone/volt`, `menu`, `minty` | No NvChad menus or color-picker UI |
| NvChad's nvim-cmp stack and sources | Replaced by Blink with LSP, path and LuaSnip sources |
| NvChad's NvimTree integration | Replaced by Neo-tree |

Re-adding NvChad's UI stack would work against the goal of keeping this
profile small and easy to manage.

### Old plugin files that were already disabled

These files contain only commented specs and were not active in the previous
profile:

| File | Experiment |
|---|---|
| `codecompanion.lua` | CodeCompanion chat and inline AI workflows |
| `kustomize.lua` | Kustomize build, resource and validation commands |
| `local-highlight.lua` | Local same-word highlighting |
| `yaml-companion.lua` | Interactive YAML schema selection and Telescope integration |

## Potential additions reviewed

These sources are documented for later decisions. None of them is enabled by
this section.

| Source | What it does | Overlap with `nvim2` | Recommendation |
|---|---|---|---|
| [MiniMax configs](https://nvim-mini.org/MiniMax/configs/) | Generates a Neovim configuration built mostly from `mini.nvim`, with version-specific examples for `vim.pack`, native LSP, Treesitter, formatting and snippets | `nvim2` already uses `vim.pack`, eight Mini modules, native LSP, Treesitter and Conform; MiniMax alternatives for files, picking, completion, snippets, sessions, Git and key hints would replace active plugins | Use it as a reference and borrow individual Mini modules; do not replace the current profile |
| [diffbandit.nvim](https://github.com/CoreyKaylor/diffbandit.nvim) | Shows two-way diffs without padding either document, using a connector gutter; also provides editable targets, file and folder diffs, Git queues, staging, a commit panel, branch and commit review, binary hex diffs and a three-way merge resolver | Gitsigns already covers signs, hunk navigation, staging, reset, preview and blame, but it does not provide a full review, folder-diff or merge UI | Trial it only if Git review or conflict resolution inside Neovim becomes a regular workflow; otherwise keep Gitsigns |
| [tunnelvision.nvim](https://github.com/leolaurindo/tunnelvision.nvim) | Dims unrelated lines around a selected symbol and navigates its path; static, dynamic and experimental flow modes use LSP highlights, Treesitter or word matching | The current LSP setup already highlights document references on cursor hold and Telescope searches references; TunnelVision adds a focused presentation and assignment-flow view | Skip initially; add only if symbol-focused reading is useful enough to justify another visual mode |
| [nvim_native](https://github.com/smnatale/nvim_native) | Demonstrates a zero-plugin setup using native LSP and completion, `findfunc` fuzzy search, ripgrep with quickfix, netrw, a custom statusline and basic format-on-save | Blink, Telescope, Neo-tree, Mini statusline and Conform already provide those workflows | Keep as a dependency-reduction reference, not an addition. The repository currently has no license, so do not copy its code unless that changes |

### MiniMax modules worth considering

`mini.nvim` is already installed, so enabling another Mini module does not add
a plugin dependency. It still adds mappings and behavior that need maintenance.

| Module | What it adds | Recommendation |
|---|---|---|
| `mini.trailspace` | Highlights trailing whitespace and exposes a trim function | Consider it for filetypes not covered by format-on-save; it is unnecessary where Conform already cleans the file |
| `mini.bracketed` | Provides consistent `[` and `]` navigation for buffers, diagnostics, quickfix, jumps and other targets | Enable only selected targets because its defaults can collide with Gitsigns hunk keys and native diagnostic keys |
| `mini.jump` and `mini.jump2d` | Extend `f`/`t` movement and add label-based jumps within visible text | Similar benefit to Flash; keep native movement until this becomes a repeated navigation problem |
| `mini.operators` | Adds exchange, multiply, replace, sort and evaluate operators | Do not enable wholesale because its default `gr` family overlaps Neovim's LSP mappings; configure individual operators if needed |
| Other MiniMax modules | Add a file browser, picker, completion, snippets, sessions, Git helpers, diff signs, key hints, color highlighting, pairs and UI elements | Avoid the overlapping replacements while Neo-tree, Telescope, Blink, LuaSnip, Gitsigns, which-key and the current color tools remain enabled |

## Suggested minimal path

Keep the current plugin set unchanged for normal use before restoring old
features. Then add only in response to a repeated workflow problem:

1. Add TODO mappings if TODO navigation is used regularly. This adds no
   dependency; prefer `<leader>tn` and `<leader>tp` instead of overriding
   built-in tag keys.
2. Keep Neo-tree as the only sidebar browser; do not add a second file-tree
   plugin.
3. Use the enabled `mini.splitjoin` first; add Treesj only if its pattern-based
   behavior is not accurate enough.
4. Trial DiffBandit only if full Git review, folder diffs or merge resolution
   are regular in-editor tasks.
5. Consider Spectre only for frequent interactive project-wide replacements.
6. Use Mini Visits labels before considering Harpoon for repeated jumps among
   a small working set.
7. Avoid re-adding cosmetic UI plugins, alternate completion stacks, NvChad
   platform plugins, or language plugins outside the supported language list.

This keeps each addition tied to an observed daily need and avoids rebuilding
the previous distribution one plugin at a time.
