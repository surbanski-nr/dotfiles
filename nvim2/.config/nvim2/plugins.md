# Nvim2 plugins

Enabled plugins, local modules, automatic behavior, and configuration choices
for the `nvim2` profile.

## Enabled plugin set

None of these plugins is bundled with Neovim. `vim.pack` downloads every one
from its own repository. “Kickstart module” means the configuration file came
with the Kickstart template, not that the plugin comes with Neovim.

| Plugin                      | Configuration source                                 | Purpose in this profile                                                                                          |
| --------------------------- | ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `blink.cmp`                 | Main `init.lua`                                      | Complete from `lsp`, `path` and `snippets` with the Lua matcher and Neovim's native snippet engine |
| `conform.nvim`              | `lua/custom/conform.lua`                             | Format manually and on save, including Ruff formatting for Python                                                |
| `fidget.nvim`               | Main `init.lua`                                      | Show language-server progress without a permanent UI panel                                                       |
| `gitsigns.nvim`             | Kickstart module enabled by the custom loader        | Show Git changes and provide hunk, blame and diff actions                                                        |
| `guess-indent.nvim`         | Main `init.lua`                                      | Detect indentation settings from the current file                                                                |
| `indent-blankline.nvim`     | Custom module                                        | Draw narrow indentation guides and mark the current Treesitter scope                                             |
| `mason-lspconfig.nvim`      | Main `init.lua`                                      | Connect Mason-installed servers to Neovim's LSP configuration names                                              |
| `mason-tool-installer.nvim` | Main `init.lua` plus `lua/custom/lsp.lua`            | Install pinned servers, formatters and linters only when explicitly requested                                    |
| `mason.nvim`                | Main `init.lua`                                      | Provide the external-tool registry, installer and `:Mason` interface                                             |
| `mini.nvim`                 | Main `init.lua` plus custom module                   | Supply eight independent module roles and one helper-only indentation generator, detailed below |
| `neo-tree.nvim`             | Kickstart module enabled by the custom loader        | Provide the sidebar filesystem browser and file operations                                                       |
| `nvim-lint`                 | Custom module                                        | Publish Actionlint, ESLint, Hadolint, TFLint and yamllint results as diagnostics                                 |
| `nvim-lspconfig`            | Main `init.lua`                                      | Supply default commands, filetypes and root detection for language servers                                       |
| `nvim-dap`                  | `lua/custom/plugins/debug.lua`, `lua/custom/debug.lua` | DAP client, breakpoints, stepping and REPL for Python |
| `nvim-dap-python`           | Python debug module                                  | Connect pinned debugpy and run cursor-selected Python tests |
| `nvim-dap-ui`               | Python debug module                                  | Show scopes, stacks, watches, console and controls during a session |
| `nvim-nio`                  | DAP UI dependency                                    | Async runtime for the debugger panels |
| `nvim-treesitter`           | Main `init.lua` plus custom tooling and fold modules | Install parsers and queries used by Neovim's built-in Treesitter runtime                                         |
| `nui.nvim`                  | Neo-tree dependency                                  | Supply popup and layout components required by Neo-tree                                                          |
| `plenary.nvim`              | Telescope and Neo-tree dependency                    | Supply shared Lua utilities required by those plugins                                                            |
| `render-markdown.nvim`      | Custom module                                        | Render Markdown headings, lists, tables and code blocks inside Neovim                                            |
| `telescope-ui-select.nvim`  | `lua/custom/telescope.lua`                           | Display `vim.ui.select` choices in a Telescope dropdown                                                          |
| `telescope.nvim`            | Main `init.lua` plus custom search module            | Search files, text, buffers, commands, symbols and diagnostics, including non-ignored dotfiles                   |
| `todo-comments.nvim`        | Main `init.lua`                                      | Highlight and search TODO-style comments                                                                         |
| `which-key.nvim`            | Main `init.lua`                                      | Discover configured prefixes, marks, registers and spelling choices; not a popup after every native key |

Neovim itself supplies `vim.pack`, the LSP client, the Treesitter runtime,
diagnostic APIs, netrw and the default colorscheme. In particular,
`nvim-lspconfig` and `nvim-treesitter` are external plugins despite their
names.

`lua/custom/plugins/init.lua` explicitly lists enabled extension modules.
External-plugin modules own their `vim.pack.add` declaration and setup. Local
feature modules install nothing. Remove a module's `require` from that loader
to disable it. Project-mark persistence is a local feature, not a session plugin.

Configuration that must run at a specific point in Kickstart stays directly
under `lua/custom/` and is called from a small seam in `init.lua`:

| Module                        | Responsibility                                                                                |
| ----------------------------- | --------------------------------------------------------------------------------------------- |
| `core.lua`                    | Options, filetype detection, register behavior, general commands and autocommands             |
| `checks.lua` and `health.lua` | Inspect real locked checkouts and tools through `:Nvim2Check`; the health module only reports shared check results |
| `lsp.lua`                     | Language-server configuration and pinned Mason tool versions                                  |
| `debug.lua`                   | Python launch/attach configurations, interpreter selection, DAP panels and mappings |
| `conform.lua`                 | Formatter selection and format-on-save controls                                               |
| `project.lua`                 | Canonical nearest-Git-root discovery shared by search and project marks                        |
| `pairs.lua`                   | Treesitter-confirmed delimiter ranges shared by highlighting and tab-out                      |
| `tabout.lua`                  | Bounded forward/backward navigation out of supported syntax pairs                             |
| `telescope.lua`               | Hidden-aware workspace, nearest-Git-root and document-symbol searches                          |
| `telescope_query.lua`         | Parse bounded Telescope query terms, escapes, anchors, negation and OR groups                  |
| `telescope_sorter.lua`        | Adapt Telescope's Lua fzy scoring, filtering and highlighting to the local query syntax        |
| `treesitter.lua`              | Managed parser list, native folds and explicit tool-install command                           |

The query adapter adds no dependency, binary, FFI or build step. It delegates
fuzzy matching to the locked Telescope Lua fzy implementation. Native fzf and
its build hooks remain disabled, so the existing offline procedure is
unchanged.

`:Nvim2Check` calls `:checkhealth custom`; `health.lua` reports every category
returned by `checks.run()`, while the headless suite calls `assert_all()` to
fail the process. Plugin verification reads each checkout's real Git HEAD and
tracked status with bounded local commands. It does not trust cached pack
metadata, fetch, repair or update dependencies. The runtime suite also contains
isolated real-repository regressions for the failure paths.

| Local feature module       | Purpose                                                                                           | External plugin added                            |
| -------------------------- | ------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| `default_colors.lua`       | Apply and reapply local syntax, search-lens and Matrix colors to the built-in default theme        | No                                               |
| `highlight_enclosing_pairs.lua` | Highlight the nearest enclosing `()`, `[]` or `{}` while the cursor is inside it              | No; extends Neovim's built-in `MatchParen` style |
| `matrix.lua`               | Draw a bounded temporary Matrix overlay over ordinary panes in the current tab                     | No                                               |
| `mermaid_ascii.lua`        | Preview the Mermaid fence under the cursor in a scrollable scratch tab                            | No; invokes the optional `mermaid-ascii` binary  |
| `project_marks.lua`        | Store and navigate persistent named positions scoped to canonical Git roots                        | No                                               |
| `scroll_marker.lua`        | Show an experimental one-cell marker for the current position at the right edge                   | No                                               |
| `search_lens.lua`          | Show one bounded native search count in the active window                                          | No                                               |
| `treesitter_selection.lua` | Three remapped aliases to native `van`/`an`/`in`, preserving parser-first and capable LSP fallback | No                                               |
| `toggle_values.lua`        | Add `<leader>tv` for boolean-like values without `nvim-toggler`                                   | No                                               |
| `snippets.lua`             | Add five global delimiter pairs and six Markdown expansions with Neovim's built-in snippet engine | No                                               |

Some plugins work automatically or only support another plugin, so they do not
need a daily key sequence:

| Plugin                                                                | Day-to-day behavior                                                                                                                               |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `guess-indent.nvim`                                                   | Detects indentation when a buffer opens; use `:GuessIndent` to run it again and `:setlocal shiftwidth? tabstop? expandtab?` to inspect the result |
| `indent-blankline.nvim`                                               | Draws narrow grey `▏` guides and a white `▏` for the current scope; toggle them with `<leader>ti` or `:IBLToggle`                                 |
| `fidget.nvim`                                                         | Shows transient LSP progress; `:Fidget history` contains retained Fidget notifications, not default progress or all editor messages |
| `mason-lspconfig.nvim`, `mason-tool-installer.nvim`, `nvim-lspconfig` | Connect configured language servers; inspect them with `:Mason` and install pinned versions with `:Nvim2ToolsInstallSync`                         |
| `nvim-treesitter`                                                     | Supplies parsing, highlighting, indentation and injections automatically for installed languages                                                  |
| `nvim-lint`                                                           | Runs configured linters after save; publishes diagnostics with filetype/project restrictions |
| `nvim-dap`, `nvim-dap-python`, `nvim-dap-ui`, `nvim-nio`                | Python-only debugging with pinned debugpy; panels open only for an initialized session and close after its last session ends |
| `nui.nvim`, `plenary.nvim`                                            | Runtime libraries for Neo-tree and Telescope; there is nothing to invoke directly                                                                 |
| `telescope-ui-select.nvim`                                            | Shows `vim.ui.select` prompts, including custom project-mark choices, in a Telescope dropdown                                                     |

Fidget keeps its defaults: `progress.display.skip_history=true` excludes
progress from retained history, and `notification.override_vim_notify=false`
does not route all editor notifications through it. Use `:messages` for
ordinary editor message history.

### Mini module ownership

The locked Mini checkout supplies eight existing roles. Setup is not needed
for every library API, and Icons is conditional:

| Module | Enabled use |
| --- | --- |
| `mini.ai` | Enhanced textual objects, `aN`/`iN` next prefixes, native `an`/`in` preserved, and custom `I` indentation object |
| `mini.surround` | `sa`/`sd`/`sr`, bracket/quote/call/tag surroundings, direction/count/repeat support |
| `mini.align` | `ga`/`gA` local delimiter alignment and preview modifiers |
| `mini.splitjoin` | `gS` comma-separated list split/join |
| `mini.jump2d` | Guarded Normal-only visible-character jump in the current ordinary pane |
| `mini.bufremove` | API-only current/other-buffer removal without `setup()`, retaining local safety guards |
| `mini.statusline` | Automatic Git/diff, diagnostics, LSP/search and location sections; Gitsigns supplies existing Git/diff fallback |
| `mini.icons` | Conditional Nerd Font setup and web-devicons mock, no action key |

Separately, `mini.extra` is used only as a library for
`gen_ai_spec.indent()` inside Mini.ai's setup. It is not set up wholesale;
Mini Pick/Indentscope/Move/Jump/Operators/Pairs/Git/Diff/Bracketed are not
enabled. Native `f/F/t/T`, `gr*`, `gx` and tag-list `[t`/`]t` retain their
existing roles. See the [Mini recipes](guide.md#mini-editing-modules) and
[native selection/clipboard flow](guide.md#expand-or-shrink-a-selection-and-copy-it-to-another-application).

Mini Jump2d is an enabled submodule of the already locked `mini.nvim`
checkout. `<leader>j` starts its single-character flow only in the current
ordinary editing window; the plugin's default `<CR>` mapping is disabled.
Project marks, the search lens, tab-out and Matrix are local modules and add no
dependency or plugin-lock entry. The local `pairs.lua` helper only shares
Treesitter delimiter discovery between tab-out and the enclosing-pair
highlighter.

Neo-tree's existing `filesystem.bind_to_cwd=true` couples its sidebar root
with tab-local cwd. Root navigation can therefore change lowercase Telescope
search scope; a window-local cwd can override the tab. Uppercase Git-root
searches and canonical project marks remain independent. The
[Neo-tree guide](guide.md#neo-tree) documents this policy and the existing
buffer/Git-status views without adding a cwd abstraction.

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
The small local `highlight_enclosing_pairs.lua` module keeps the nearest pair orange while
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
overrides. Restart Neovim after editing it, or run `:source $MYVIMRC`. The
module reapplies its overrides after `:colorscheme`, including the search-lens
and Matrix groups.

## Plugin decisions and migration history

The archived-profile comparison, disabled Kickstart examples, rejected
plugins and future candidates are maintained outside this repository. They are
not part of the daily workflow or the enabled dependency list.
