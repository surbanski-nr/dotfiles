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

The Bash configuration also provides the `v` alias. To start directly from
this repository:

```bash
cd /home/surbanski/work/githubactions/dotfilesneovim/dotfiles/nvim2/.config/nvim2
XDG_CONFIG_HOME="$(dirname "$PWD")" NVIM_APPNAME=nvim2 nvim
```

Use current Neovim 0.12 stable or a recent nightly. Language installation and
tooling details are in
[`docs/neovim-nvchad-to-kickstart.md`](../../../docs/neovim-nvchad-to-kickstart.md).

## Enabled plugin set

| Plugin | Purpose in this profile |
|---|---|
| `LuaSnip` | Expand the custom global, Lua and Markdown snippets under `snippets/` |
| `blink.cmp` | Provide completion from LSP, filesystem paths and LuaSnip |
| `conform.nvim` | Format manually and on save, including Ruff formatting for Python |
| `fidget.nvim` | Show language-server progress without a permanent UI panel |
| `gitsigns.nvim` | Show Git changes and provide hunk, blame and diff actions |
| `guess-indent.nvim` | Detect indentation settings from the current file |
| `mason-lspconfig.nvim` | Connect Mason-installed servers to Neovim's LSP configuration names |
| `mason-tool-installer.nvim` | Install the selected servers, formatters and linters automatically |
| `mason.nvim` | Provide the external-tool registry, installer and `:Mason` interface |
| `mini.nvim` | Supply text objects, surroundings, alignment, statusline, icons and buffer removal |
| `neo-tree.nvim` | Provide the sidebar filesystem browser and file operations |
| `nvim-highlight-colors` | Preview color values inline |
| `nvim-lint` | Publish Hadolint, TFLint and yamllint results as diagnostics |
| `nvim-lspconfig` | Supply default commands, filetypes and root detection for language servers |
| `nvim-treesitter` | Provide parsing, highlighting, indentation and language injections |
| `nui.nvim` | Supply popup and layout components required by Neo-tree |
| `persistence.nvim` | Save and restore directory-based sessions |
| `plenary.nvim` | Supply shared Lua utilities required by Telescope |
| `render-markdown.nvim` | Render Markdown headings, lists, tables and code blocks inside Neovim |
| `telescope-fzf-native.nvim` | Speed up Telescope sorting with its compiled FZF matcher |
| `telescope-ui-select.nvim` | Display `vim.ui.select` choices in a Telescope dropdown |
| `telescope.nvim` | Search files, text, buffers, commands, symbols and diagnostics |
| `todo-comments.nvim` | Highlight and search TODO-style comments |
| `which-key.nvim` | Show available mappings after a key prefix |

Most plugin setup is intentionally kept in `init.lua`. Persistence,
render-markdown and color highlighting are installed and configured together
in `SECTION 4: UI / CORE UX PLUGINS`. Telescope, LSP, Conform, completion and
Treesitter have their own numbered sections. Gitsigns, linting and Neo-tree use
files under `lua/kickstart/plugins/`. The `lua/custom/plugins/` loader remains
disabled, so placing a file there does not currently enable it.

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
| Delete line | `dd` |
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
| Add an empty line below or above | `]<Space>`, `[<Space>` |
| Show registers | `:registers` |
| Paste latest explicit yank | `"0p` |
| Paste from numbered yank ring | `"1p` through `"9p` |
| Use system clipboard explicitly | `"+y`, `"+p` |

This profile changes register behavior:

- `c`, `C`, `cc`, and visual `c` use the black-hole register, so changing text
  does not overwrite the latest yank.
- Visual `p` preserves the latest yank instead of replacing it with the
  selected text.
- Successful yanks are copied into registers `1` through `9` as a small yank
  ring.
- `clipboard=unnamedplus` is enabled, so normal yanks and pastes also use the
  system clipboard when a clipboard provider is available.

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
buffers. The profile uses marker folds (`{{{` and `}}}`).

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
| Expand to outer LSP selection range | `an` in visual/operator-pending mode |
| Shrink to inner LSP selection range | `in` in visual/operator-pending mode |

Treesitter provides syntax highlighting, indentation, injections and parser
support automatically. It has no custom daily mapping in this profile. The
`an` and `in` mappings above are Neovim 0.12 LSP selection ranges, while
Mini.ai uses `aa` and `ii` for its next-textobject variants.

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

Blink supplies completion from LSP, paths and LuaSnip. Custom global, Lua and
Markdown snippets live under `snippets/`.

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
| Inspect or install external tools | `:Mason` |
| Install all managed tools and parsers synchronously | `:Nvim2ToolsInstallSync` |

Conform formats configured filetypes on save. `<leader>tf` is useful when one
Neovim process is opened for a repository that should not be reformatted. The
toggle lasts for that process and does not change repository files or settings.
Manual formatting with `<leader>f` remains available while format-on-save is
disabled. Ruff sorts imports and formats Python. `nvim-lint` runs configured
CLI linters after saving; it has no manual mapping.

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

## Sessions, Markdown, colors and TODO comments

| Action | Keys or command |
|---|---|
| Restore session for current directory | `<leader>pr` |
| Select a saved session | `<leader>ps` |
| Toggle Markdown rendering globally | `:RenderMarkdown toggle` |
| Toggle Markdown rendering for current buffer | `:RenderMarkdown buf_toggle` |
| Open a side-by-side rendered Markdown preview | `:RenderMarkdown preview` |
| Toggle inline color previews | `:HighlightColors Toggle` |
| Search TODO comments | `:TodoTelescope` |
| Put TODO comments in quickfix | `:TodoQuickFix` |

The old TODO mappings (`]t`, `[t`, `<leader>ft`, `<leader>tq`) have not been
restored. Adding mappings requires no new plugin because
`todo-comments.nvim` is already installed. Prefer `<leader>tn` and
`<leader>tp` for TODO navigation: `[t`/`]t` and `[T`/`]T` are Neovim's
built-in tag-list mappings.

## Plugin and configuration maintenance

| Action | Command |
|---|---|
| Inspect plugin state without network access | `:lua vim.pack.update(nil, { offline = true })` |
| Fetch and review plugin updates | `:lua vim.pack.update()` |
| Apply proposed plugin updates | `:write` in the update window |
| Cancel proposed plugin updates | `:quit` in the update window |
| Check profile health | `:checkhealth kickstart` |
| Check LSP health | `:checkhealth vim.lsp` |
| Check Treesitter health | `:checkhealth nvim-treesitter` |

Commit `nvim-pack-lock.json` whenever accepted plugin revisions change.

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

To enable a disabled module, uncomment its `require` line near the bottom of
`init.lua` and restart Neovim. Neo-tree is enabled; its common daily keys are:

| Action in Neo-tree | Keys |
|---|---|
| Reveal current file or focus tree | `\` |
| Open file or expand directory | `<CR>` or `<Space>` |
| Preview file | `P` |
| Open in horizontal split, vertical split or tab | `S`, `s`, `t` |
| Close directory or all directories | `C`, `z` |
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
   then press `<CR>`.
3. To rename an item, select it, press `r`, edit the name and press `<CR>`.
4. To move or copy an item directly, press `m` or `c`, enter its destination
   path and press `<CR>`.
5. To move or copy through the tree, mark an item with `x` or `y`, select the
   destination directory and press `p`.
6. To remove an item, select it, press `d` and confirm the prompt.

Neo-tree refreshes after these operations. Press `?` inside the tree if a
less common action or current mapping is needed.

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
| `gbprod/cutlass.nvim` | Partly replaced by black-hole change mappings | Deletes can still alter delete registers; use `"_d` when that matters |
| `lewis6991/gitsigns.nvim` | Kept | New profile has more hunk, diff and blame mappings |
| `lukas-reineke/headlines.nvim` | Replaced by `render-markdown.nvim` | Browser rendering is still separate from in-editor rendering |
| `mfussenegger/nvim-lint` | Kept | Linter set is limited to the selected development languages |
| `neovim/nvim-lspconfig` | Kept | Uses the Neovim 0.12 API and the selected server list |
| `mason-org/mason.nvim` | Kept | Mason LSP and tool installers now manage the complete selected tool set |
| `olimorris/persisted.nvim` | Replaced by `folke/persistence.nvim` | Session picker mappings changed to `<leader>pr` and `<leader>ps` |
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
| `ThePrimeagen/harpoon` | Persistent short list of frequently used files | Consider later only if `<leader><leader>` is too slow for repeated file switching |
| `tzachar/highlight-undo.nvim` | Briefly highlighted text affected by undo and redo | Cosmetic; do not add |
| `kevinhwang91/nvim-hlslens` | Search match counts and search markers integrated with scrollbar | Neovim search count and normal `n`/`N` are sufficient |
| `iamcco/markdown-preview.nvim` | Browser-based Markdown preview | Add only when browser-accurate rendering is needed; current render-markdown is in-editor |
| `karb94/neoscroll.nvim` | Animated smooth scrolling | Cosmetic; do not add |
| `shortcuts/no-neck-pain.nvim` | Centered editing column with side padding | Cosmetic; use splits when focus space is needed |
| `nacro90/numb.nvim` | Previewed a target line while entering `:<line>` | Small convenience; do not add initially |
| `epwalsh/pomo.nvim` and `nvim-notify` | Pomodoro timers and notifications | Keep time management outside the editor |
| `tris203/precognition.nvim` | On-screen hints for available Vim motions | Useful while learning, but not part of a stable daily setup |
| `ahmedkhalf/project.nvim` | Project-root detection and Telescope project switching | Sessions, current working directory and file search cover the common cases |
| `petertriho/nvim-scrollbar` | Scrollbar with diagnostic and search markers | Cosmetic; signs, diagnostics and Telescope already expose this information |
| `utilyre/sentiment.nvim` | Enhanced matching-pair highlighting | Built-in match highlighting is enough |
| `nvim-pack/nvim-spectre` | Interactive project-wide search and replace | Consider only if project-wide replacements are frequent; otherwise use quickfix plus `:cdo` |
| `cshuaimin/ssr.nvim` | Treesitter structural search and replace | Add only for recurring AST-aware refactors |
| `nguyenvukhang/nvim-toggler` | Toggled values such as `true`/`false` or `on`/`off` | Small convenience; a mapping or substitution is simpler than another plugin |
| `nvim-tree/nvim-tree.lua` | Persistent sidebar file explorer | Replaced by the enabled Neo-tree module |
| `Wansmer/treesj` | Split or joined syntax nodes with `gj` | Try `mini.splitjoin` first because Mini is already installed; reconsider Treesj only if syntax-aware splitting is needed |
| `folke/trouble.nvim` | Dedicated diagnostics, references and quickfix-style panels | Telescope diagnostics and location lists cover the common workflow |
| `kevinhwang91/nvim-ufo` and `promise-async` | Treesitter/indent folds and fold previews | Keep marker folds initially; configure native Treesitter folds before adding a plugin |
| `szw/vim-maximizer` | Toggled the current split between normal and maximized size | Use built-in window sizing commands such as `<C-w>_` and `<C-w>=`, or add a small mapping later |
| `sustech-data/wildfire.nvim` | Repeatedly expanded visual selection to surrounding objects | Mini.ai text objects and LSP `an`/`in` selections cover most cases |

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
| [MiniMax configs](https://nvim-mini.org/MiniMax/configs/) | Generates a Neovim configuration built mostly from `mini.nvim`, with version-specific examples for `vim.pack`, native LSP, Treesitter, formatting and snippets | `nvim2` already uses `vim.pack`, six Mini modules, native LSP, Treesitter and Conform; MiniMax alternatives for files, picking, completion, snippets, sessions, Git and key hints would replace active plugins | Use it as a reference and borrow individual Mini modules; do not replace the current profile |
| [diffbandit.nvim](https://github.com/CoreyKaylor/diffbandit.nvim) | Shows two-way diffs without padding either document, using a connector gutter; also provides editable targets, file and folder diffs, Git queues, staging, a commit panel, branch and commit review, binary hex diffs and a three-way merge resolver | Gitsigns already covers signs, hunk navigation, staging, reset, preview and blame, but it does not provide a full review, folder-diff or merge UI | Trial it only if Git review or conflict resolution inside Neovim becomes a regular workflow; otherwise keep Gitsigns |
| [tunnelvision.nvim](https://github.com/leolaurindo/tunnelvision.nvim) | Dims unrelated lines around a selected symbol and navigates its path; static, dynamic and experimental flow modes use LSP highlights, Treesitter or word matching | The current LSP setup already highlights document references on cursor hold and Telescope searches references; TunnelVision adds a focused presentation and assignment-flow view | Skip initially; add only if symbol-focused reading is useful enough to justify another visual mode |
| [nvim_native](https://github.com/smnatale/nvim_native) | Demonstrates a zero-plugin setup using native LSP and completion, `findfunc` fuzzy search, ripgrep with quickfix, netrw, a custom statusline and basic format-on-save | Blink, Telescope, Neo-tree, Mini statusline and Conform already provide those workflows | Keep as a dependency-reduction reference, not an addition. The repository currently has no license, so do not copy its code unless that changes |

### MiniMax modules worth considering

`mini.nvim` is already installed, so enabling another Mini module does not add
a plugin dependency. It still adds mappings and behavior that need maintenance.

| Module | What it adds | Recommendation |
|---|---|---|
| `mini.splitjoin` | Toggles bracketed arguments between one line and one item per line with `gS` | Try it for JSON, Lua, Terraform and YAML flow collections; use Treesj if syntax-aware structures need better coverage |
| `mini.trailspace` | Highlights trailing whitespace and exposes a trim function | Consider it for filetypes not covered by format-on-save; it is unnecessary where Conform already cleans the file |
| `mini.bracketed` | Provides consistent `[` and `]` navigation for buffers, diagnostics, quickfix, jumps and other targets | Enable only selected targets because its defaults can collide with Gitsigns hunk keys and native diagnostic keys |
| `mini.visits` | Tracks file and directory visits for frecency search and user labels | Consider only if Telescope buffers, old files and persistence sessions are not enough |
| `mini.jump` and `mini.jump2d` | Extend `f`/`t` movement and add label-based jumps within visible text | Similar benefit to Flash; keep native movement until this becomes a repeated navigation problem |
| `mini.operators` | Adds exchange, multiply, replace, sort and evaluate operators | Do not enable wholesale because its default `gr` family overlaps Neovim's LSP mappings; configure individual operators if needed |
| Other MiniMax modules | Add a file browser, picker, completion, snippets, sessions, Git helpers, diff signs, key hints, color highlighting, pairs and UI elements | Avoid the overlapping replacements while Neo-tree, Telescope, Blink, LuaSnip, persistence, Gitsigns, which-key and the current color tools remain enabled |

## Suggested minimal path

Keep the current plugin set unchanged for normal use before restoring old
features. Then add only in response to a repeated workflow problem:

1. Add TODO mappings if TODO navigation is used regularly. This adds no
   dependency; prefer `<leader>tn` and `<leader>tp` instead of overriding
   built-in tag keys.
2. Keep Neo-tree as the only sidebar browser; do not add a second file-tree
   plugin.
3. Try `mini.splitjoin` first if split/join operations are frequent. It uses the
   existing Mini dependency; add Treesj only if its pattern-based behavior is
   not accurate enough.
4. Trial DiffBandit only if full Git review, folder diffs or merge resolution
   are regular in-editor tasks.
5. Consider Spectre only for frequent interactive project-wide replacements.
6. Consider Harpoon only if the buffer picker does not cover repeated jumps
   among a small working set.
7. Avoid re-adding cosmetic UI plugins, alternate completion stacks, NvChad
   platform plugins, or language plugins outside the supported language list.

This keeps each addition tied to an observed daily need and avoids rebuilding
the previous distribution one plugin at a time.
