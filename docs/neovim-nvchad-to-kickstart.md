# Neovim migration: NvChad (`nvim/`) -> Kickstart (`nvim2/`)

This document compares the two Neovim configurations currently in this repo:

- **Current (NvChad-based)**: `nvim/.config/nvim` (loads `NvChad/NvChad` `branch = "v2.5"` via lazy.nvim)
- **Target (Kickstart-based)**: `nvim2` (run with `NVIM_APPNAME=nvim2 nvim`)

Goal: help you understand what you’ll **lose**, what will be **different**, and where your **keybind muscle-memory will break** when moving from your current NvChad setup to your Kickstart setup.

## TL;DR

You keep (already present in Kickstart):

- LSP via `neovim/nvim-lspconfig` + `mason-org/mason.nvim`
- Telescope (`nvim-telescope/telescope.nvim`)
- Treesitter (`nvim-treesitter/nvim-treesitter`)
- Git signs (`lewis6991/gitsigns.nvim`)
- Formatting (`stevearc/conform.nvim`)
- Linting (`mfussenegger/nvim-lint`)
- which-key (`folke/which-key.nvim`)
- Autopairs, indent guides

You lose (because it’s specific to NvChad and/or your NvChad add-ons):

- NvChad UI stack (theme engine + statusline + tab/buffer UI + extras)
- NvimTree file explorer (replaced by Neo-tree)
- nvim-cmp completion stack (replaced by blink.cmp)
- Many “workflow helpers” you added (harpoon, trouble, spectre, yanky, etc.)

Expectation check:

- **Yes, it’s expected that you don’t see a “buffer list” across the top in Kickstart.** NvChad shows buffers via its tabufline/UI; your Kickstart config does not enable a bufferline/tabline. Use `<leader><leader>` (Telescope buffers) instead.

## Plugins

The lists below were derived from:

- NvChad base plugins (upstream `NvChad/NvChad` v2.5): `lua/nvchad/plugins/init.lua`
- Your NvChad custom plugins: `nvim/.config/nvim/lua/plugins/*.lua`
- Your Kickstart plugins: `nvim2/init.lua` and `nvim2/lua/kickstart/plugins/*.lua`

### Plugins present in both

- `L3MON4D3/LuaSnip`
- `folke/todo-comments.nvim`
- `folke/which-key.nvim`
- `lewis6991/gitsigns.nvim`
- `lukas-reineke/indent-blankline.nvim`
- `mason-org/mason.nvim`
- `mfussenegger/nvim-lint`
- `neovim/nvim-lspconfig`
- `nvim-lua/plenary.nvim`
- `nvim-telescope/telescope.nvim`
- `nvim-tree/nvim-web-devicons`
- `nvim-treesitter/nvim-treesitter`
- `stevearc/conform.nvim`
- `windwp/nvim-autopairs`

### Plugins you will miss (present in NvChad config, not present in Kickstart)

NvChad “platform/UI” (you lose the experience even if some underlying tools remain):

- `nvchad/base46` (theme engine + highlight pipeline)
- `nvchad/ui` (statusline, tabufline/buffers UI, UI glue)
- `nvzone/volt`, `nvzone/menu`, `nvzone/minty` (NvChad UI add-ons)
- `nvim-tree/nvim-tree.lua` (file explorer; replaced by Neo-tree)

Completion + AI (big workflow difference):

- `hrsh7th/nvim-cmp` and companions:
  - `hrsh7th/cmp-buffer`
  - `hrsh7th/cmp-nvim-lsp`
  - `hrsh7th/cmp-nvim-lua`
  - `saadparwaiz1/cmp_luasnip`
  - `rafamadriz/friendly-snippets`
- Copilot:
  - `zbirenbaum/copilot.lua`
  - `zbirenbaum/copilot-cmp`
  - `jonahgoldwastaken/copilot-status.nvim`

Search / navigation / refactoring helpers:

- `ThePrimeagen/harpoon`
- `folke/flash.nvim`
- `rmagatti/goto-preview`
- `cshuaimin/ssr.nvim` (structural search/replace UI)
- `nvim-pack/nvim-spectre` (project search/replace)
- `Wansmer/treesj` (split/join nodes)
- `nacro90/numb.nvim` (line preview while typing a number)

Diagnostics / tooling UI:

- `folke/trouble.nvim`
- `kevinhwang91/nvim-bqf` (better quickfix)
- `kevinhwang91/nvim-ufo` + `kevinhwang91/promise-async` (folding)

Editing ergonomics:

- `numToStr/Comment.nvim` + `JoosepAlviste/nvim-ts-context-commentstring`
- `kylechui/nvim-surround`
- `gbprod/yanky.nvim` (yank history + remaps)
- `gbprod/cutlass.nvim` (delete without polluting yank register)
- `nguyenvukhang/nvim-toggler` (toggle words via keybind)
- `sustech-data/wildfire.nvim` (expand selection)

Docs / markdown:

- `iamcco/markdown-preview.nvim`
- `lukas-reineke/headlines.nvim`

UI polish / focus / motion:

- `shortcuts/no-neck-pain.nvim`
- `petertriho/nvim-scrollbar`
- `karb94/neoscroll.nvim`
- `kevinhwang91/nvim-hlslens`
- `tzachar/highlight-undo.nvim`
- `utilyre/sentiment.nvim`
- `tris203/precognition.nvim`
- `rcarriga/nvim-notify`
- `epwalsh/pomo.nvim`

Sessions / project management:

- `ahmedkhalf/project.nvim`
- `olimorris/persisted.nvim`

Language-specific (your current NvChad config adds these):

- `ray-x/go.nvim` (+ `ray-x/guihua.lua`)
- `pearofducks/ansible-vim`
- `towolf/vim-helm`

### Plugins that are new in Kickstart (not present in your NvChad config)

- `saghen/blink.cmp` (replaces the nvim-cmp stack)
- `nvim-neo-tree/neo-tree.nvim` (+ `MunifTanjim/nui.nvim`) (replaces nvim-tree)
- `nvim-mini/mini.nvim` (adds `mini.ai`, `mini.surround`, `mini.statusline` in your config)
- `NMAC427/guess-indent.nvim`
- `WhoIsSethDaniel/mason-tool-installer.nvim`
- Debugger stack (you enabled kickstart’s debug module):
  - `mfussenegger/nvim-dap`
  - `rcarriga/nvim-dap-ui`
  - `nvim-neotest/nvim-nio`
  - `jay-babu/mason-nvim-dap.nvim`
  - `leoluz/nvim-dap-go`
- Telescope extras:
  - `nvim-telescope/telescope-fzf-native.nvim`
  - `nvim-telescope/telescope-ui-select.nvim`
- `j-hui/fidget.nvim` (LSP status UI)
- `folke/tokyonight.nvim` (colorscheme)

### Same plugin, different behavior/config (things you might “miss” anyway)

Even for plugins present in both configs, behavior can differ a lot:

- **Telescope keymaps**: NvChad defaults are under `<leader>f...`; Kickstart uses `<leader>s...` (details in Keymaps section).
- **`folke/todo-comments.nvim`**: you currently have custom keymaps in NvChad; your Kickstart config loads the plugin but does not define those keymaps.
- **`mfussenegger/nvim-lint`**:
  - NvChad config (`nvim/.config/nvim/lua/configs/linting.lua`) defines many linters and a manual trigger mapping `<leader>cl`.
  - Kickstart config (`nvim2/lua/kickstart/plugins/lint.lua`) only configures `markdownlint` and has no manual trigger mapping.
- **`stevearc/conform.nvim`**:
  - NvChad config (`nvim/.config/nvim/lua/configs/conform.lua`) formats many filetypes (python/js/go/terraform/etc).
  - Kickstart config (`nvim2/init.lua`) only configures `stylua` by default.
- **LSP servers + tooling**:
  - NvChad enables many servers in `nvim/.config/nvim/lua/configs/lspconfig.lua` and installs many tools via `nvim/.config/nvim/lua/configs/mason.lua`.
  - Kickstart currently ensures only `pyright` + `stylua` via `mason-tool-installer` in `nvim2/init.lua`. Note: `lua_ls` is enabled, but it is not included in `ensure_installed` (so you may need to install it yourself).
- **Treesitter language coverage**:
  - NvChad ensures many languages (`nvim/.config/nvim/lua/configs/treesitter.lua`).
  - Kickstart installs a smaller set and uses `vim.treesitter.start()` per filetype (`nvim2/init.lua`).

## Keymaps: what changes (and what breaks)

Leader key:

- NvChad: `vim.g.mapleader = " "` (`nvim/.config/nvim/init.lua`)
- Kickstart: `vim.g.mapleader = ' '` (`nvim2/init.lua`)

### “Buffer list only shows one file” (expected behavior)

NvChad:

- Shows buffers in a “tabline-like” UI via `nvchad/ui` (tabufline).
- Default buffer navigation includes `<tab>`, `<S-tab>`, `<leader>x`, etc (depends on NvChad UI settings).

Kickstart:

- Does not show a buffer list/tabline by default (you are using `mini.statusline`, not a bufferline/tabline).
- Use:
  - `<leader><leader>` (Telescope buffers) (`nvim2/init.lua`)
  - `:ls`, `:bnext`, `:bprev` (built-in)

### High-impact keymap differences (common actions)

Action | NvChad (current) | Kickstart (nvim2)
---|---|---
Open file explorer | `<C-n>` toggles NvimTree | `\\` reveals Neo-tree
Find files | `<leader>ff` | `<leader>sf`
Find *all* files (incl hidden/ignored) | `<leader>fa` | no equivalent keymap by default
Live grep | `<leader>fw` | `<leader>sg`
Buffers picker | `<leader>fb` | `<leader><leader>`
Help tags | `<leader>fh` | `<leader>sh`
Keymaps picker | (no default) | `<leader>sk`
Commands picker | (no default) | `<leader>sc`
Fuzzy find in current buffer | `<leader>fz` | `<leader>/` (note: this conflicts with NvChad’s comment toggle)
Rename symbol | `<leader>sr` (NvChad renamer) | `grn`
Code action | (varies; often `<leader>ca`) | `gra`
Format | `gm` (your custom map) | `<leader>f`
Quit all | `<leader>qq` | no equivalent mapping by default

Notes on conflicts:

- NvChad uses `<leader>/` for comment toggling; Kickstart uses `<leader>/` for “fuzzy search in current buffer”.
- NvChad remaps `gO`/`go` to add blank lines; Kickstart uses `gO` for LSP document symbols when LSP attaches.

### Keymaps you currently have (NvChad custom overrides)

From `nvim/.config/nvim/lua/mappings.lua`:

- `;` -> `:` (command-line)
- Insert: `jk` -> `<Esc>`
- `J` -> join line without moving cursor
- Visual indent: `>` / `<` keep selection
- Insert: `<C-BS>` deletes previous word
- `<leader>+` / `<leader>-` increment/decrement number
- `<leader>qq` quit all without saving
- `<leader>al` open Lazy UI
- `<leader>sr` NvChad renamer
- `<leader>ch` signature help
- `<leader>fc` telescope git commits
- `<leader>fs` telescope git status
- `<leader>fm` telescope marks (note: differs from NvChad default `<leader>fm` = format)
- `<leader>fl` telescope yaml_schema (requires yaml-companion extension; currently not enabled in your plugins)
- `gh` / `gt` jump to first/last screen character
- `gO` / `go` insert blank lines above/below
- `gm` format via conform
- `<leader>aa` toggle completion (enables/disables cmp in buffer)
- `<leader>af` toggle diff mode across windows
- `<leader>aq` toggle quickfix window
- `<leader>z` close all buffers except current
- Centering helpers: `<C-d>`, `<C-u>`, `n`, `N`
- Move lines: `<A-j>`, `<A-k>` (normal + visual)

### Keymaps you will lose (from NvChad plugins you’re not carrying over)

These come from your NvChad plugin specs (`nvim/.config/nvim/lua/plugins/*.lua`) and will not exist in Kickstart unless you re-add/configure them later.

Navigation/search helpers:

- `ThePrimeagen/harpoon` (`nvim/.config/nvim/lua/plugins/harpoon.lua`)
  - `<leader>mm` add
  - `<leader>ml` list
  - `<leader>mn` next, `<leader>mp` prev, `<leader>mr` remove
  - `<leader>1`..`<leader>9` select
  - `<leader>fr` telescope picker for harpoon list
- `folke/flash.nvim` (`nvim/.config/nvim/lua/plugins/flash.lua`)
  - `ss` flash jump
  - `st` flash treesitter
  - `<leader>sr` remote flash (operator mode)
  - `<leader>su` treesitter search (operator/visual)
- `rmagatti/goto-preview` (`nvim/.config/nvim/lua/plugins/goto-preview.lua`)
  - `gpd` definition, `gpi` implementation, `gpr` references, `gpt` type def, `gpc` close
- `cshuaimin/ssr.nvim` (`nvim/.config/nvim/lua/plugins/ssr.lua`)
  - `<leader>sx` open SSR
  - Inside SSR UI: `q` close, `n` next match, `N` prev match, `<cr>` confirm, `<leader><cr>` replace all
- `nvim-pack/nvim-spectre` (`nvim/.config/nvim/lua/plugins/spectre.lua`)
  - `<leader>ar` toggle
  - `<leader>so` open
  - `<leader>sw` search word (visual/cursor)
  - `<leader>sf` search in current file
  - Note: these collide with Kickstart’s `<leader>sw` and `<leader>sf` meanings.
- `Wansmer/treesj` (`nvim/.config/nvim/lua/plugins/treesj.lua`)
  - `gj` toggle split/join

Editor UX:

- `gbprod/yanky.nvim` (`nvim/.config/nvim/lua/plugins/yanky.lua`)
  - Changes default `y`, `p`, etc to yank-history aware mappings
  - Adds yank history cycling: `[y` / `]y`
  - Adds `<leader>fy` to open yank history via Telescope
- `nguyenvukhang/nvim-toggler` (`nvim/.config/nvim/lua/plugins/toggler.lua`)
  - `gk` toggle word under cursor (normal/visual)
- `szw/vim-maximizer` (`nvim/.config/nvim/lua/plugins/vim-maximizer.lua`)
  - `<leader>am` maximize/minimize split
- `okuuva/auto-save.nvim` (`nvim/.config/nvim/lua/plugins/auto-save.lua`)
  - `<leader>as` toggle autosave

Diagnostics/notes:

- `folke/trouble.nvim` (`nvim/.config/nvim/lua/plugins/trouble.lua`)
  - `<leader>at` toggle Trouble diagnostics
- `folke/todo-comments.nvim` (`nvim/.config/nvim/lua/plugins/todo-comments.lua`)
  - `[t` / `]t` jump between todos
  - `<leader>ft` TodoTelescope
  - `<leader>tq` TodoQuickFix
  - Note: Kickstart loads todo-comments but does not define these keymaps.

Focus/timers:

- `shortcuts/no-neck-pain.nvim` (`nvim/.config/nvim/lua/plugins/no-neck-pain.lua`)
  - `<leader>tn` toggle NoNeckPain
- `tris203/precognition.nvim` (`nvim/.config/nvim/lua/plugins/precognition.lua`)
  - `<leader>an` toggle Precognition
- `epwalsh/pomo.nvim` (`nvim/.config/nvim/lua/plugins/pomo.lua`)
  - `<leader>ts` start timer
  - `<leader>to` stop
  - `<leader>tp` pause
  - `<leader>tr` resume

Markdown:

- `iamcco/markdown-preview.nvim` (`nvim/.config/nvim/lua/plugins/markdown-preview.lua`)
  - `<leader>ap` toggle markdown preview

### Kickstart keymaps you gain (or that are different)

From `nvim2/init.lua` and `nvim2/lua/kickstart/plugins/*.lua`:

Core:

- `<Esc>` clears search highlight (normal mode)
- `<Esc><Esc>` exits terminal-mode in the built-in terminal
- `<C-h>`, `<C-j>`, `<C-k>`, `<C-l>` window navigation (same idea as NvChad)
- `<leader>q` opens diagnostics location list

Telescope (Kickstart style):

- `<leader>sf` files
- `<leader>sg` live grep
- `<leader>sw` grep string under cursor (normal + visual)
- `<leader><leader>` buffers
- `<leader>s.` recent files
- `<leader>sh` help tags
- `<leader>sk` keymaps
- `<leader>sc` commands
- `<leader>sd` diagnostics
- `<leader>sr` resume last telescope picker
- `<leader>/` fuzzy find within current buffer
- `<leader>s/` live grep in open files
- `<leader>sn` search Neovim config files

LSP (Kickstart style):

- `grd` definition, `gri` implementation, `grr` references, `grt` type definition (via Telescope)
- `gO` document symbols, `gW` workspace symbols (via Telescope)
- `grn` rename, `gra` code action, `grD` declaration
- `<leader>th` toggle inlay hints (if supported by server)

Formatting:

- `<leader>f` format buffer (Conform)

File explorer (Neo-tree):

- `\\` reveal Neo-tree (and `\\` to close the Neo-tree window when focused)

Debugging (DAP):

- `<F5>` continue, `<F1>` step into, `<F2>` step over, `<F3>` step out
- `<leader>b` toggle breakpoint, `<leader>B` conditional breakpoint
- `<F7>` toggle DAP UI

Mini.nvim (new muscle memory vs nvim-surround):

- Surround keys come from `mini.surround` (Kickstart), not `nvim-surround` (NvChad).
  - Kickstart: `sa` add, `sd` delete, `sr` replace (see comments near the `mini.surround` setup in `nvim2/init.lua`)

## “Show hidden and ignored files” (what you asked to keep)

You asked to keep behavior like NvChad/NvimTree where you can see hidden and gitignored files.

### NvChad / NvimTree behavior you currently have

- In NvimTree you can toggle filters:
  - `H` toggles dotfiles
  - `I` toggles gitignored
  - (see the reminder comments in `nvim/.config/nvim/lua/plugins/tree.lua`)
- In Telescope, NvChad provides:
  - `<leader>fa` => `find_files follow=true no_ignore=true hidden=true` (from upstream NvChad mappings)

### Kickstart equivalents (no new plugins; config-only suggestions)

Neo-tree: set it to show everything by default by configuring `filesystem.filtered_items`.

Suggested change (in `nvim2/lua/kickstart/plugins/neo-tree.lua`):

```lua
opts = {
  filesystem = {
    filtered_items = {
      visible = true,
      hide_dotfiles = false,
      hide_gitignored = false,
    },
  },
}
```

Telescope: add an “all files” mapping similar to NvChad’s `<leader>fa`.

Suggested keymap (inside the Telescope config in `nvim2/init.lua`):

```lua
vim.keymap.set('n', '<leader>sa', function()
  builtin.find_files { hidden = true, no_ignore = true, follow = true }
end, { desc = '[S]earch [A]ll files (hidden + ignored)' })
```

If you want “live grep including hidden/ignored”, you typically also want ripgrep args like `--hidden` + `--no-ignore` + a `.git` exclude.

## Summary: what you’re really “missing”

If your goal is “minimal and start from scratch”, the biggest practical losses are:

- **Bufferline/tabufline UI** (and the related buffer navigation keymaps)
- **Your extra workflow plugins** (harpoon, spectre/ssr, trouble, yanky)
- **Your broad language tooling** (mason ensure list, linters/formatters across many languages)
- **Copilot + statusline modules**
- **Surround keymap muscle memory** (`nvim-surround` vs `mini.surround`)

And the biggest “unexpected” differences are mostly keymap collisions:

- `<leader>/`, `<leader>sf`, `<leader>sw`, `<leader>sr`, and `gO` mean different things now.

