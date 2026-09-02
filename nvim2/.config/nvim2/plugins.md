# Nvim2 plugins

Enabled plugins, local modules, automatic behavior, and configuration choices
for the `nvim2` profile.

## Enabled plugin set

None of these plugins is bundled with Neovim. `vim.pack` downloads every one
from its own repository. “Kickstart module” means the configuration file came
with the Kickstart template, not that the plugin comes with Neovim.

| Plugin                      | Configuration source                                 | Purpose in this profile                                                                                          |
| --------------------------- | ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `blink.cmp`                 | Main `init.lua`                                      | Provide completion from LSP and filesystem paths, then expand LSP snippets with Neovim's built-in snippet engine |
| `conform.nvim`              | `lua/custom/conform.lua`                             | Format manually and on save, including Ruff formatting for Python                                                |
| `fidget.nvim`               | Main `init.lua`                                      | Show language-server progress without a permanent UI panel                                                       |
| `gitsigns.nvim`             | Kickstart module enabled by the custom loader        | Show Git changes and provide hunk, blame and diff actions                                                        |
| `guess-indent.nvim`         | Main `init.lua`                                      | Detect indentation settings from the current file                                                                |
| `indent-blankline.nvim`     | Custom module                                        | Draw narrow indentation guides and mark the current Treesitter scope                                             |
| `mason-lspconfig.nvim`      | Main `init.lua`                                      | Connect Mason-installed servers to Neovim's LSP configuration names                                              |
| `mason-tool-installer.nvim` | Main `init.lua` plus `lua/custom/lsp.lua`            | Install pinned servers, formatters and linters only when explicitly requested                                    |
| `mason.nvim`                | Main `init.lua`                                      | Provide the external-tool registry, installer and `:Mason` interface                                             |
| `mini.nvim`                 | Main `init.lua` plus custom module                   | Supply text objects, surroundings, alignment, split/join, visited files, statusline, icons and buffer removal    |
| `neo-tree.nvim`             | Kickstart module enabled by the custom loader        | Provide the sidebar filesystem browser and file operations                                                       |
| `nvim-lint`                 | Custom module                                        | Publish Actionlint, ESLint, Hadolint, TFLint and yamllint results as diagnostics                                 |
| `nvim-lspconfig`            | Main `init.lua`                                      | Supply default commands, filetypes and root detection for language servers                                       |
| `nvim-treesitter`           | Main `init.lua` plus custom tooling and fold modules | Install parsers and queries used by Neovim's built-in Treesitter runtime                                         |
| `nui.nvim`                  | Neo-tree dependency                                  | Supply popup and layout components required by Neo-tree                                                          |
| `plenary.nvim`              | Telescope and Neo-tree dependency                    | Supply shared Lua utilities required by those plugins                                                            |
| `render-markdown.nvim`      | Custom module                                        | Render Markdown headings, lists, tables and code blocks inside Neovim                                            |
| `telescope-ui-select.nvim`  | `lua/custom/telescope.lua`                           | Display `vim.ui.select` choices in a Telescope dropdown                                                          |
| `telescope.nvim`            | Main `init.lua` plus custom search module            | Search files, text, buffers, commands, symbols and diagnostics, including non-ignored dotfiles                   |
| `todo-comments.nvim`        | Main `init.lua`                                      | Highlight and search TODO-style comments                                                                         |
| `which-key.nvim`            | Main `init.lua` plus the Mini Visits key group       | Show available mappings after a key prefix                                                                       |

Neovim itself supplies `vim.pack`, the LSP client, the Treesitter runtime,
diagnostic APIs, netrw and the default colorscheme. In particular,
`nvim-lspconfig` and `nvim-treesitter` are external plugins despite their
names.

Every Lua file under `lua/custom/plugins/` is loaded by Kickstart's standard
custom-extension loop. External-plugin modules own their `vim.pack.add`
declaration and setup. Local feature modules install nothing. Move or delete a
module to disable it; leaving a module in this directory enables it on the next
start. There is no persistence module or session plugin in this profile.

Configuration that must run at a specific point in Kickstart stays directly
under `lua/custom/` and is called from a small seam in `init.lua`:

| Module                        | Responsibility                                                                                |
| ----------------------------- | --------------------------------------------------------------------------------------------- |
| `core.lua`                    | Options, filetype detection, register behavior, general commands and autocommands             |
| `checks.lua` and `health.lua` | Validate locked dependencies through `:Nvim2Check`; behavior lives in the headless smoke test |
| `lsp.lua`                     | Language-server configuration and pinned Mason tool versions                                  |
| `conform.lua`                 | Formatter selection and format-on-save controls                                               |
| `telescope.lua`               | Hidden-aware workspace searches and nearest-Git-root searches                                 |
| `treesitter.lua`              | Managed parser list, native folds and explicit tool-install command                           |

| Local feature module       | Purpose                                                                                           | External plugin added                            |
| -------------------------- | ------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| `default_colors.lua`       | Apply local syntax and navigation colors to the built-in default colorscheme                      | No                                               |
| `enclosing_pairs.lua`      | Highlight the nearest enclosing `()`, `[]` or `{}` pair while the cursor is anywhere inside it    | No; extends Neovim's built-in `MatchParen` style |
| `mermaid_ascii.lua`        | Preview the Mermaid fence under the cursor in a scrollable scratch tab                            | No; invokes the optional `mermaid-ascii` binary  |
| `scroll_marker.lua`        | Show an experimental one-cell marker for the current position at the right edge                   | No                                               |
| `treesitter_selection.lua` | Add simple keys for Neovim's built-in syntax-aware selection expansion                            | No                                               |
| `toggle_values.lua`        | Add `<leader>tv` for boolean-like values without `nvim-toggler`                                   | No                                               |
| `snippets.lua`             | Add five global delimiter pairs and six Markdown expansions with Neovim's built-in snippet engine | No                                               |

Some plugins work automatically or only support another plugin, so they do not
need a daily key sequence:

| Plugin                                                                | Day-to-day behavior                                                                                                                               |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `guess-indent.nvim`                                                   | Detects indentation when a buffer opens; use `:GuessIndent` to run it again and `:setlocal shiftwidth? tabstop? expandtab?` to inspect the result |
| `indent-blankline.nvim`                                               | Draws narrow grey `▏` guides and a white `▏` for the current scope; toggle them with `<leader>ti` or `:IBLToggle`                                 |
| `fidget.nvim`                                                         | Shows LSP progress in a temporary notification; use `:Fidget history` to inspect earlier messages                                                 |
| `mason-lspconfig.nvim`, `mason-tool-installer.nvim`, `nvim-lspconfig` | Connect configured language servers; inspect them with `:Mason` and install pinned versions with `:Nvim2ToolsInstallSync`                         |
| `nvim-treesitter`                                                     | Supplies parsing, highlighting, indentation and injections automatically for installed languages                                                  |
| `nvim-lint`                                                           | Runs configured linters after save and publishes their results through the diagnostic workflow below                                              |
| `nui.nvim`, `plenary.nvim`                                            | Runtime libraries for Neo-tree and Telescope; there is nothing to invoke directly                                                                 |
| `telescope-ui-select.nvim`                                            | Shows `vim.ui.select` prompts, including Mini Visits choices, in a Telescope dropdown                                                             |

The active colorscheme is Neovim's built-in `default` with its dark
`NvimDark*` palette and a small set of local overrides in `lua/custom/plugins/default_colors.lua`.

Indent guides use the narrow solid `▏` character and the visible `#4f5358`
grey from the default palette. The current Treesitter scope changes the same
width `▏` guide to the default white foreground, without horizontal start or
end markers. The active scope follows nested blocks in Bash, Lua, Python,
TypeScript and YAML. Bash control flow and Python compound statements are
included explicitly because the plugin defaults otherwise stop at their
enclosing function. Lua table constructors are also included. YAML scope ends
are adjusted to their last content line because Treesitter otherwise reports
the following dedent and moves the active guide to column zero. The lockfile
pins its tested revision. Toggle all guides with
`<leader>ti` or `:IBLToggle`;
toggle only the active-scope marker with `:IBLToggleScope`. Change the
characters or colors in
`lua/custom/plugins/indent_guides.lua` if they are still too visible.

Neovim's built-in `matchparen` plugin highlights a matching `()`, `[]` or `{}`
pair in orange when the cursor is on or immediately after one of the brackets.
The small local `enclosing_pairs.lua` module keeps the nearest pair orange while
the cursor is anywhere inside it. It walks upward through the current
Treesitter node instead of scanning the file, and silently does nothing for a
filetype without an installed parser. Press `%` on a bracket to jump to its
match. Use `:NoMatchParen` and `:DoMatchParen` to disable or restore only the
built-in behavior for the current session. Red is deliberately avoided because
the palette uses it for errors.

The white indent line marks the innermost Treesitter scope, not the cursor's
literal indentation column. In the `library = vim.tbl_extend(..., { ... })`
example it belongs to that innermost `{ ... }` table and is drawn at the
table's content-indent boundary. This can differ from a function's or outer
table's guide.

### Adjust the colorscheme

Edit `lua/custom/plugins/default_colors.lua` to experiment with the local
overrides. Restart Neovim after editing it, or run `:source $MYVIMRC`. Running
`:colorscheme default` later in a session clears the overrides until the next
restart or source.

## Plugin decisions and migration history

The archived-profile comparison, disabled Kickstart examples, rejected
plugins and future candidates are maintained outside this repository. They are
not part of the daily workflow or the enabled dependency list.
