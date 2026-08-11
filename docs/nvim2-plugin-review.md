# Nvim2 plugin review

This document keeps migration history and plugin decisions out of the daily
[Nvim2 guide](../nvim2/.config/nvim2/README.md). It is not an installation
list. The current enabled set is documented in the Nvim2 guide and locked in
`nvim-pack-lock.json`.

## Kickstart example modules

Files under `lua/kickstart/plugins/` are examples bundled with Kickstart. A
module is active only when the Nvim2 configuration requires it and its plugin
is present in the lockfile.

| Module | State | Decision |
|---|---|---|
| `gitsigns.lua` | Enabled | Adds the Git mappings documented in the daily guide |
| `neo-tree.lua` | Enabled | Provides the only sidebar file browser |
| `lint.lua` | Replaced | The custom module uses Actionlint, Hadolint, TFLint and yamllint |
| `indent_line.lua` | Replaced | The custom module controls the guide appearance |
| `debug.lua` | Disabled | Do not add DAP until an actual debugging workflow requires it |
| `autopairs.lua` | Disabled | Native snippets already provide the wanted delimiter pairs |

A disabled module's `vim.pack.add` call is not executed. Its dependency must
also be absent from `nvim-pack-lock.json`, because a clean `vim.pack` setup
restores every lockfile entry.

## Previous profile comparison

The archived profile uses NvChad v2.5 and contains 48 files under
`old-nvim/.config/old-nvim/lua/plugins/`: 44 active configurations and four
commented experiments.

### Kept, replaced or partly covered

| Previous plugin | Status in Nvim2 | Difference that remains |
|---|---|---|
| `hrsh7th/nvim-cmp` | Replaced by `blink.cmp` | Blink omits buffer-word and Copilot completion |
| `numToStr/Comment.nvim` and `nvim-ts-context-commentstring` | Replaced by Neovim's `gc` and Treesitter-aware comments | No meaningful daily feature is missing |
| `stevearc/conform.nvim` | Kept | Nvim2 has broader format-on-save rules and uses Ruff for Python |
| `gbprod/cutlass.nvim` | Partly replaced by black-hole change and delete mappings | `x`, `X` and explicit register operations retain normal cut behavior |
| `lewis6991/gitsigns.nvim` | Kept | Nvim2 adds hunk, diff, blame and quickfix mappings |
| `lukas-reineke/headlines.nvim` | Replaced by `render-markdown.nvim` | Browser rendering remains separate |
| `mfussenegger/nvim-lint` | Kept | Linters are limited to the supported development languages |
| `neovim/nvim-lspconfig` | Kept | Uses the Neovim 0.12 API and selected server list |
| `mason-org/mason.nvim` | Kept | Tools have exact versions and explicit installation |
| `olimorris/persisted.nvim` | Removed | Reopen files through Mini Visits, Telescope or Neo-tree |
| `kylechui/nvim-surround` | Replaced by `mini.surround` | Mappings use Mini's `sa`, `sd` and `sr` grammar |
| `nvim-telescope/telescope.nvim` | Kept | Search mappings and hidden-file rules changed |
| `folke/todo-comments.nvim` | Kept | Old TODO mappings and gutter signs are disabled |
| `nvim-treesitter/nvim-treesitter` | Kept | Parsers are limited to supported languages |
| `pearofducks/ansible-vim` | Replaced | Filetype detection, Treesitter and Ansible LSP cover the normal workflow |
| `towolf/vim-helm` | Replaced | Filetype detection, Treesitter and Helm LSP cover the normal workflow |
| `gbprod/yanky.nvim` | Partly replaced | Registers `1` through `9` provide a small yank ring without a picker |

### Features intentionally left out

| Previous plugin | What it provided | Current decision |
|---|---|---|
| `okuuva/auto-save.nvim` | Saved after edits or leaving Insert mode | Keep explicit saves so formatting and lint timing remain predictable |
| `kevinhwang91/nvim-bqf` | Quickfix previews and filtering | Use built-in quickfix until a repeated limitation appears |
| `zbirenbaum/copilot.lua` and integration plugins | AI completion | Add only `copilot.lua` if AI completion is intentionally wanted |
| `folke/flash.nvim` | Label jumps and Treesitter selection | Use native movement, Telescope and Treesitter selection |
| `ray-x/go.nvim` and `guihua.lua` | Go tools and commands | Add `gopls` first if Go returns to the supported language list |
| `rmagatti/goto-preview` | Definitions and references in floating previews | Use Telescope LSP pickers |
| `ThePrimeagen/harpoon` | Persistent short file list | Use uppercase marks and Mini Visits labels |
| `tzachar/highlight-undo.nvim` | Undo and redo highlights | Cosmetic, so leave it out |
| `kevinhwang91/nvim-hlslens` | Search counts and scrollbar markers | Use Neovim search count and `n`/`N` |
| `iamcco/markdown-preview.nvim` | Browser Markdown preview | Use in-editor rendering until browser accuracy is needed |
| `karb94/neoscroll.nvim` | Animated scrolling | Cosmetic, so leave it out |
| `shortcuts/no-neck-pain.nvim` | Centered editing column | Use splits |
| `nacro90/numb.nvim` | Previewed `:<line>` jumps | Keep normal line jumps |
| `epwalsh/pomo.nvim` and `nvim-notify` | Pomodoro and notifications | Keep time management outside the editor |
| `tris203/precognition.nvim` | Motion hints | Consider only as a temporary learning aid |
| `ahmedkhalf/project.nvim` | Project switching | Use nearest-Git-root Telescope searches and per-tab directories |
| `petertriho/nvim-scrollbar` | Scrollbar markers | Signs, diagnostics and Telescope provide the needed information |
| `utilyre/sentiment.nvim` | Matching-pair highlighting | Neovim matchparen plus the local enclosing-pairs module replace it |
| `nvim-pack/nvim-spectre` | Interactive workspace replacement | Use the documented [Telescope and quickfix review flow](../nvim2/.config/nvim2/README.md#find-and-replace-with-review) |
| `cshuaimin/ssr.nvim` | Structural search and replace | Add only for recurring AST-aware refactors |
| `nguyenvukhang/nvim-toggler` | Boolean-like value toggling | Replaced by local `<leader>tv` |
| `nvim-tree/nvim-tree.lua` | File sidebar | Replaced by Neo-tree |
| `Wansmer/treesj` | Syntax-aware split and join | Use `mini.splitjoin` first |
| `folke/trouble.nvim` | Diagnostics and reference panels | Use Telescope, quickfix and location lists |
| `kevinhwang91/nvim-ufo` and `promise-async` | Folds and previews | Native Treesitter folds replace them except for previews |
| `szw/vim-maximizer` | Maximized current split | Use `<C-w>_` and `<C-w>=` |
| `sustech-data/wildfire.nvim` | Repeated syntax selection | Replaced by `<C-Space>` to expand and `<BS>` to shrink |

### NvChad platform features no longer present

| NvChad component | Nvim2 replacement or decision |
|---|---|
| `nvchad/base46` | Neovim's default colorscheme and optional `surb` overrides |
| `nvchad/ui` | Mini statusline; no dashboard or buffer tabline |
| `nvzone/volt`, `menu`, `minty` | No replacement because their menus and color picker are not needed |
| NvChad completion stack | Blink with LSP and paths plus Neovim snippets |
| NvChad NvimTree integration | Neo-tree |

Reintroducing the NvChad UI stack would work against the small-profile goal.

### Previously disabled experiments

These files were already commented out in the archived profile:

| File | Experiment |
|---|---|
| `codecompanion.lua` | CodeCompanion chat and inline AI workflows |
| `kustomize.lua` | Kustomize resource and validation commands |
| `local-highlight.lua` | Same-word highlighting |
| `yaml-companion.lua` | Interactive YAML schema selection |

## Reviewed candidates

None of these sources is installed by this section.

| Source | What it does | Decision |
|---|---|---|
| [MiniMax configs](https://nvim-mini.org/MiniMax/configs/) | Shows configurations built mostly from Mini modules | Keep as a reference and borrow only individual non-overlapping modules |
| [diffbandit.nvim](https://github.com/CoreyKaylor/diffbandit.nvim) | Full Git review, folder diffs and merge UI | Do not add; Gitsigns covers the required workflow |
| [tunnelvision.nvim](https://github.com/leolaurindo/tunnelvision.nvim) | Dims unrelated code and follows symbol flow | Do not add unless symbol-focused reading becomes a regular need |
| [nvim_native](https://github.com/smnatale/nvim_native) | Demonstrates plugin-free LSP, search and UI | Keep as a dependency-reduction reference; do not copy unlicensed code |

`mini.nvim` is already installed, so enabling another Mini module adds no new
repository but still adds mappings and behavior:

| Module | Decision |
|---|---|
| `mini.trailspace` | Consider only for filetypes not cleaned by formatting |
| `mini.bracketed` | Enable individual targets only because defaults can collide with Gitsigns and diagnostics |
| `mini.jump` and `mini.jump2d` | Keep native movement until label-based jumps solve a repeated problem |
| `mini.operators` | Do not enable wholesale because its `gr` mappings overlap LSP |

## Current policy

- Keep Neo-tree as the only sidebar browser.
- Use Mini Splitjoin before reconsidering Treesj.
- Keep DAP and DiffBandit out of the current profile.
- Use built-in marks and Mini Visits before reconsidering Harpoon.
- Add a plugin only for an observed workflow problem, not to rebuild the old
  distribution one dependency at a time.
