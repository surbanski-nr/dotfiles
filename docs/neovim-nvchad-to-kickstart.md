# Neovim profiles

The repository keeps two Neovim profiles:

- `nvim/` is the previous NvChad configuration.
- `nvim2/.config/nvim2/` is the development profile based on
  [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim).

The Kickstart profile uses Neovim 0.12's built-in `vim.pack` package manager.
Its resolved plugin revisions are stored in `nvim-pack-lock.json`.

Use the current Neovim 0.12 stable release or a recent nightly. The installed
`0.12.0-dev` build predates parts of the final 0.12 API, so Kickstart's health
check correctly recommends upgrading it.

## Start the development profile

When `nvim2` is stowed into `~/.config/nvim2`:

```bash
NVIM_APPNAME=nvim2 nvim
```

The Bash configuration exports `NVIM_APPNAME=nvim2`, `EDITOR=nvim` and
`VISUAL=nvim`, so `nvim`, `vim`, `vi`, `v` and `ffv` use this profile by
default. Use `vn` to open the previous `~/.config/nvim` profile explicitly.

To run directly from the repository without stowing it:

```bash
cd /home/surbanski/work/githubactions/dotfilesneovim/dotfiles/nvim2/.config/nvim2
XDG_CONFIG_HOME="$(dirname "$PWD")" NVIM_APPNAME=nvim2 nvim
```

## Language tooling

| Files | Language server | Formatter | Linter |
|---|---|---|---|
| Python | Pyright and Ruff | Ruff import sorting and formatting | Ruff |
| Dockerfile and Compose | Docker Language Server | LSP fallback | Hadolint |
| Bash and POSIX shell | Bash Language Server | shfmt | ShellCheck |
| Lua | Lua Language Server | StyLua | Lua Language Server |
| Terraform | Terraform Language Server | `terraform fmt` | TFLint |
| Ansible | Ansible Language Server | yamlfmt | ansible-lint and yamllint |
| Helm | Helm Language Server | No automatic template formatter | `helm lint` |
| YAML | YAML Language Server | yamlfmt | yamllint |
| CSS | CSS Language Server | Prettier | Language server diagnostics |
| JSON | JSON Language Server | Prettier | Language server diagnostics |
| Markdown | Markdown Oxide | Prettier | Markdown Oxide diagnostics |
| TOML | Taplo | Taplo | Taplo diagnostics |

Ruff replaces Black, isort, and Flake8. Conform runs
`ruff_organize_imports` followed by `ruff_format` for Python.

Format-on-save is enabled for the configured languages and common web file
types. Helm templates are excluded because generic YAML formatters can damage
Go template expressions. Use `:FormatDisable` globally or `:FormatDisable!`
for the current buffer; use `:FormatEnable` or `:FormatEnable!` to restore it.
Press `<leader>tf` to toggle format-on-save for the current Neovim process.

CLI linters run after saving. Expensive project-wide tools such as TFLint do
not run on every insert-mode change.

## Plugins added to Kickstart

- `persistence.nvim` is retained as a disabled optional module.
- `render-markdown.nvim` renders Markdown headings, tables, checkboxes, and
  code blocks in the editor.
- `nvim-highlight-colors` previews color values inline.
- `nvim-lint` publishes Hadolint, TFLint, and yamllint results as diagnostics.

Kickstart's Telescope, which-key, and Mini statusline remain in place. The
profile does not add FzfLua, Lualine, Mini Clue, inc-rename, navic, Copilot,
or vim-tmux-navigator.

Mini provides surround and text objects from Kickstart, plus alignment,
split/join, frecent file visits and buffer removal. Press `gS` to split or join
a bracketed argument list and `Ctrl+x` to remove the current buffer.

## Editing behavior

- Relative line numbers, rounded floating-window borders, wrapped-line
  indentation and visible trailing whitespace are enabled. Supported
  filetypes use native Treesitter folds; marker folds remain the fallback.
- Changes use the black-hole register so they do not replace the latest yank.
- Visual-mode paste preserves the latest yank.
- Successful yanks are retained in a numbered yank ring.
- Spell checking is enabled for Markdown, text, and Git commit messages.
- The last cursor position is restored and splits rebalance after a terminal
  resize.
- Direct SSH sessions use Neovim's OSC 52 clipboard provider. Tmux uses
  `set-clipboard external`, so tmux copy-mode selections reach the terminal
  clipboard while OSC 52 writes from applications inside tmux are blocked.

The active colorscheme is Neovim's built-in `default` with its dark
`NvimDark*` palette. The retained Isekai colorscheme and palette are disabled;
the custom LuaSnip snippets remain active. See

## Key commands

See the [`nvim2` README](../nvim2/.config/nvim2/README.md) for the full daily
key reference, bundled optional modules, and previous-plugin comparison.

| Action | Command or mapping |
|---|---|
| Format buffer or selection | `<leader>f` |
| Remove current buffer | `Ctrl+x` |
| Split or join bracketed arguments | `gS` |
| Select visited files in current workspace | `<leader>vv` |
| Toggle a boolean-like value | `<leader>tv` |
| Next or previous Git hunk | `]c` / `[c` |
| Stage or reset Git hunk | `<leader>hs` / `<leader>hr` |
| Preview Git hunk | `<leader>hp` |
| Blame current line | `<leader>hb` |
| Search files | `<leader>sf` |
| Search text | `<leader>sg` |
| Search files in nearest Git root | `<leader>sF` |
| Search text in nearest Git root | `<leader>sG` |
| Search buffers | `<leader><leader>` |

## Install and verify

Plugin installation happens during the first launch. Mason tools and
Treesitter parsers are version-pinned and are not installed or updated during
normal startup. Provision them explicitly on a connected trusted machine:

```bash
cd /home/surbanski/work/githubactions/dotfilesneovim/dotfiles/nvim2/.config/nvim2
timeout 600s env XDG_CONFIG_HOME="$(dirname "$PWD")" NVIM_APPNAME=nvim2 \
  nvim --headless '+Nvim2ToolsInstallSync' '+qa!'
```

The Ansible language server also needs an `ansible` executable on `PATH`:

```bash
sudo apt install ansible-core
```

Terraform, Helm, and Docker remain project or system dependencies rather than
Mason-managed runtimes.

Verify the setup inside Neovim:

```vim
:Mason
:checkhealth vim.lsp
:ConformInfo
:checkhealth kickstart
```

Update plugins with `:lua vim.pack.update()`, review the changes, and use
`:write` to apply them and refresh `nvim-pack-lock.json`. Mason versions are
pinned separately in `init.lua`; change a pin before running
`:Nvim2ToolsInstallSync`. The complete workflow is in
[`Plugin and configuration maintenance`](../nvim2/.config/nvim2/README.md#plugin-and-configuration-maintenance).
