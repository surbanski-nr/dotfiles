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

The Bash configuration provides the same command through the `v` alias.

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

CLI linters run after saving. Expensive project-wide tools such as TFLint do
not run on every insert-mode change.

## Plugins added to Kickstart

- `persistence.nvim` saves and restores sessions.
- `render-markdown.nvim` renders Markdown headings, tables, checkboxes, and
  code blocks in the editor.
- `nvim-highlight-colors` previews color values inline.
- `nvim-lint` publishes Hadolint, TFLint, and yamllint results as diagnostics.

Kickstart's Telescope, which-key, and Mini statusline remain in place. The
profile does not add FzfLua, Lualine, Mini Clue, inc-rename, navic, Copilot,
or vim-tmux-navigator.

Mini provides surround and text objects from Kickstart, plus `mini.align` and
buffer removal. Press `Ctrl+x` to remove the current buffer.

## Editing behavior

- Relative line numbers, rounded floating-window borders, wrapped-line
  indentation, visible trailing whitespace, and marker folds are enabled.
- Changes use the black-hole register so they do not replace the latest yank.
- Visual-mode paste preserves the latest yank.
- Successful yanks are retained in a numbered yank ring.
- Spell checking is enabled for Markdown, text, and Git commit messages.
- The last cursor position is restored and splits rebalance after a terminal
  resize.
- SSH sessions use Neovim's OSC 52 clipboard provider. Tmux currently has
  `set-clipboard off`, so tmux may block OSC 52 while direct SSH terminals work.

The Isekai colorscheme, palette, and custom LuaSnip snippets are adapted from

## Key commands

See the [`nvim2` README](../nvim2/.config/nvim2/README.md) for the full daily
key reference, bundled optional modules, and previous-plugin comparison.

| Action | Command or mapping |
|---|---|
| Format buffer or selection | `<leader>f` |
| Restore current session | `<leader>pr` |
| Select a session | `<leader>ps` |
| Remove current buffer | `Ctrl+x` |
| Next or previous Git hunk | `]c` / `[c` |
| Stage or reset Git hunk | `<leader>hs` / `<leader>hr` |
| Preview Git hunk | `<leader>hp` |
| Blame current line | `<leader>hb` |
| Search files | `<leader>sf` |
| Search text | `<leader>sg` |
| Search buffers | `<leader><leader>` |

## Install and verify

Plugin installation happens during the first launch. Mason installs the
configured language servers, formatters, linters, and the Treesitter CLI.
Treesitter installs its parsers after the CLI is ready. To force a synchronous
tool install:

```bash
cd /home/surbanski/work/githubactions/dotfilesneovim/dotfiles/nvim2/.config/nvim2
XDG_CONFIG_HOME="$(dirname "$PWD")" NVIM_APPNAME=nvim2 \
  nvim --headless '+MasonToolsInstallSync' '+qa'
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

Update plugins with `:lua vim.pack.update()`, review the changes, and commit
the updated `nvim-pack-lock.json` with the configuration.
