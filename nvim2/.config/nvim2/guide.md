# Nvim2 guide

Daily commands and keybindings for the `nvim2` profile. Start it with
`NVIM_APPNAME=nvim2 nvim`; the stowed Bash configuration makes it the default
Neovim profile.

The leader key is `Space`. This guide focuses on common daily tasks rather
than every Neovim command.

For a first session, learn only this flow: press `i` to edit, `Esc` to return
to Normal mode and `:w` to save; use `\` for the file tree, `<leader>sf` for
files and `<leader>sg` for text; use `grd` for a definition and `<C-o>` to jump
back; use `]d` and `[d` for diagnostics; and press `Space`, then wait, whenever
you need to discover a leader mapping. The sections below add detail as each
workflow becomes useful.

## Discover mappings inside Neovim

These are the fastest ways to find a mapping when this guide is outdated or
incomplete:

| Action                              | Command                              |
| ----------------------------------- | ------------------------------------ |
| Show the next available leader keys | Press `Space` and wait for which-key |
| Search configured mappings          | `<leader>sk`                         |
| Inspect a normal-mode mapping       | `:verbose nmap <keys>`               |
| Inspect an insert-mode mapping      | `:verbose imap <keys>`               |
| Read help for a key                 | `:help <keys>`                       |
| List commands                       | `<leader>sc`                         |

Notation used below:

- `<leader>` means `Space`.
- `<C-x>` means `Ctrl+x`.
- `<S-x>` means `Shift+x`.
- `<A-x>` means `Alt+x`.
- Normal mode is the default mode reached with `Esc`.

## Daily Neovim basics

### Files and commands

| Action                               | Keys or command      |
| ------------------------------------ | -------------------- |
| Open a file                          | `:edit path/to/file` |
| Save current file                    | `:write` or `:w`     |
| Save all changed files               | `:wall` or `:wa`     |
| Save and quit                        | `:wq`                |
| Quit current window                  | `:quit` or `:q`      |
| Quit without saving                  | `:q!`                |
| Quit Neovim                          | `:qa`                |
| Repeat the last command-line command | `@:`                 |
| Repeat the last normal-mode change   | `.`                  |
| Open path or URL under cursor        | `gx`                 |
| Open built-in directory browser      | `:Explore`           |
| Open directory browser on the left   | `:Lexplore`          |

`netrw` supplies `:Explore`. Neo-tree is the enabled sidebar browser; press
`\` to reveal the current file or focus the tree.

### Movement and search

| Action                                   | Keys                                  |
| ---------------------------------------- | ------------------------------------- |
| Move left, down, up, right               | `h`, `j`, `k`, `l`                    |
| Next or previous word                    | `w`, `b`                              |
| End of word                              | `e`                                   |
| Start, first text, or end of line        | `0`, `^`, `$`                         |
| First or last line                       | `gg`, `G`                             |
| Jump to a line                           | `<line>G`, for example `42G`          |
| Previous or next paragraph/block         | `{`, `}`                              |
| Matching bracket                         | `%`                                   |
| Half-page down or up                     | `<C-d>`, `<C-u>`                      |
| Center current line                      | `zz`                                  |
| Find character forward                   | `f<char>`                             |
| Move before character forward            | `t<char>`                             |
| Repeat or reverse character search       | `;`, `,`                              |
| Search forward or backward               | `/text`, `?text`                      |
| Next or previous search match            | `n`, `N`                              |
| Search word under cursor                 | `*` forward, `#` backward             |
| Clear search highlighting                | `<Esc>`                               |
| Jump backward or forward in jump list    | `<C-o>`, `<C-i>`                      |
| Browse and open a jump-list location     | `<leader>sj`, select, then `<Enter>`  |
| Toggle relative or absolute line numbers | `<leader>tl`                          |
| Toggle the right-edge position marker    | `<leader>ts` or `:ScrollMarkerToggle` |

`<leader>tl` changes only the current window. Line numbers stay visible: the
default relative mode is useful for motions such as `5j`, while absolute mode
is useful when discussing exact line numbers. Press `<leader>tl` again to
return to relative numbers.

The statusline location uses `current/total:column position`, for example
`47/862:1 5%`. The experimental orange dot at the right edge shows the same
approximate file position visually. It has no border and remains within the
text area above the statusline. It does not represent the visible viewport and
hides in Neo-tree, Telescope, quickfix and other non-file buffers. Toggle it
with `<leader>ts`. To remove the experiment entirely, delete
`lua/custom/plugins/scroll_marker.lua`.

### Marks and a small Harpoon-like shortlist

Marks are named positions built into Neovim. A buffer is an in-memory copy of a
file; a window is a pane that displays a buffer. Multiple split windows can
show the same buffer, and a window can switch between buffers. Marks belong to
buffers or files, not to windows.

Press plain `m` followed by a letter to save the current position. Any
lowercase letter creates a mark valid only within the current file/buffer: `ma`,
`mb`, `ms` and so on. It remains available from every window showing that
buffer, but it cannot jump from another file. Any uppercase letter creates a
file mark that also remembers the filename: `mA`, `mB`, `mS` and so on. An
uppercase jump can load another file, and uppercase marks persist through
ShaDa. For example, set `ma` for a temporary position inside the current file;
set `mA` when `A` should return to that file from anywhere. Each buffer can
have its own lowercase `a`; there is only one global uppercase `A`, and setting
`mA` elsewhere moves it.

| Action                                                      | Keys or command                    |
| ----------------------------------------------------------- | ---------------------------------- |
| Set local mark `a`                                          | `ma`                               |
| Set cross-file mark `A`                                     | `mA`                               |
| Jump to the exact row and column                            | `` `a `` or `` `A ``               |
| Jump to the marked line's first nonblank character          | `'a` or `'A`                       |
| Browse and jump to marks                                    | `<leader>sm` or `:Telescope marks` |
| List marks without Telescope                                | `:marks`                           |
| Delete named marks `a` and `A`                              | `:delmarks a A`                    |
| Delete lowercase marks `a` through `z`                      | `:delmarks a-z`                    |
| Delete uppercase and numbered marks                         | `:delmarks A-Z 0-9`                |
| Delete current-buffer marks except uppercase/numbered marks | `:delmarks!`                       |

A Harpoon-like flow is: use `mA`, `mB` and `mC` in three frequently used
places, jump back with `` `A ``, `` `B `` or `` `C ``, and browse them with
`<leader>sm`. Setting the same uppercase mark elsewhere moves it. Mini Visits
labels under `<leader>v` remain better for a larger named set of files.

The character after a backtick or single quote is the mark name. A backtick
jumps to its exact row and column; a single quote jumps to the first nonblank
character on its line. Thus `` `a `` is exact while `'a` is linewise. For the
automatic mark named `"`, the exact jump is a backtick followed by a double
quote: `` `" ``.

Neovim also maintains automatic marks, which is why `<leader>sm` shows entries
you did not create:

| Mark            | Meaning                                                   | Exact jump or related action                                            |
| --------------- | --------------------------------------------------------- | ----------------------------------------------------------------------- |
| `"`             | Cursor position when the current buffer was last exited   | `` `" ``; delete with `:delmarks \"`                                    |
| `'`             | Position before the latest jump                           | `` `' `` for exact position, or `''` for its line; it cannot be deleted |
| `0` through `9` | Files exited in recent Neovim sessions, loaded from ShaDa | `` `0 `` through `` `9 ``; delete with `:delmarks 0-9`                  |
| `.`             | Last change                                               | `` `. ``                                                                |
| `^`             | Last position where Insert mode stopped                   | `` `^ ``                                                                |
| `[` and `]`     | Start and end of the last changed or yanked text          | `` `[ `` and `` `] ``                                                   |
| `<` and `>`     | Start and end of the last visual selection                | `` `< `` and `` `> ``                                                   |

`<leader>sm` browses and jumps but does not delete. Note the mark name, close
Telescope, then use `:delmarks {name}`. `:delmarks!` also clears the current
buffer's changelist. Automatic `"` and numbered marks may reappear as Neovim
records later exits; the previous-jump mark `'` is maintained continuously.

`<leader>m` by itself has no action. It is a which-key prefix whose active
mapping is `<leader>ma` for the optional Mermaid ASCII preview.

### Editing, selection, undo and registers

| Action                                                          | Keys                                    |
| --------------------------------------------------------------- | --------------------------------------- |
| Insert before or after cursor                                   | `i`, `a`                                |
| Insert at start or end of line                                  | `I`, `A`                                |
| Open line below or above                                        | `o`, `O`                                |
| Cut character under or before cursor, replacing active register | `x`, `X`                                |
| Delete line without changing registers                          | `dd`                                    |
| Delete with a motion without changing registers                 | `d{motion}`, for example `dw` or `diw`  |
| Delete to end of line without changing registers                | `D`                                     |
| Change inside word                                              | `ciw`                                   |
| Yank line                                                       | `yy`                                    |
| Yank inside word                                                | `yiw`                                   |
| Paste after or before cursor                                    | `p`, `P`                                |
| Undo or redo                                                    | `u`, `<C-r>`                            |
| Character, line, or block selection                             | `v`, `V`, `<C-v>`                       |
| Start, expand or shrink syntax selection                        | `<C-Space>`, then `<C-Space>` or `<BS>` |
| Reselect last visual selection                                  | `gv`                                    |
| Indent or unindent selection                                    | `>`, `<`                                |
| Join current line with next                                     | `J`                                     |
| Toggle boolean-like value under cursor                          | `<leader>tv`                            |
| Toggle indentation guides                                       | `<leader>ti` or `:IBLToggle`            |
| Add an empty line below or above                                | `]<Space>`, `[<Space>`                  |
| Show registers                                                  | `:registers`                            |
| Browse and promote yank history                                 | `<leader>sy`, select, then `p` or `P`   |
| Paste latest explicit yank                                      | `"0p`                                   |
| Paste from numbered yank ring                                   | `"1p` through `"9p`                     |
| Delete a selection without changing any register                | Select text, then `"_d`                 |
| Yank into and paste from named register `a`                     | `"ay{motion}`, then `"ap`               |
| Use system clipboard explicitly                                 | `"+y`, `"+p`                            |

Registers are small text storage slots. The `"{register}` prefix selects a
register for the next operation:

- `"` is the unnamed register used by plain `y`, `x`, `X`, `p` and `P`. This
  profile sends normal `d`, `D` and `dd` operations to the black-hole register.
- `0` keeps the latest explicit yank, even after a later normal delete. Use
  `"0p` when plain `p` would paste recently deleted text instead.
- `1` through `9` form this profile's small yank history: `"1p` pastes the
  newest saved yank, `"2p` the previous one, and so on. Unmapped operations,
  such as visual `d`, can still alter numbered registers.
- `a` through `z` are manual named registers. For example, `"ayy` stores a
  line in `a`, `"ap` pastes it, and `"Ayy` appends another line to it.
- `_` is the black-hole register. Text sent there is discarded. This profile
  maps normal `d`, `D` and `dd` to it automatically. Use visual `"_d` when
  deleting a selection that should not replace text waiting to be pasted.

Use `<leader>sy` to browse the yank history in Telescope. Select an entry and
press `<Enter>` to move it to register `1` and make it the active value for
`p` or `P`. Selection does not paste or otherwise change the buffer. The other
entries retain their relative order. Use `:registers 0 1 2 3 4 5 6 7 8 9` to
inspect the history without changing its order, or `:registers` to inspect
every register.

This profile changes register behavior:

- Normal `d`, `D`, `dd`, `c`, `C`, `cc`, and visual `c` use the black-hole
  register, so these operations do not overwrite the latest yank. Built-in
  `x` and `X` retain their cut-like behavior and replace the active register.
- Visual `P` uses Neovim's built-in paste-without-overwriting behavior. Visual
  `p` keeps its standard behavior and replaces the active register with the
  selected text.
- Successful yanks are copied into registers `1` through `9` as a small yank
  ring.
- `clipboard=unnamedplus` is enabled, so normal yanks and pastes also use the
  system clipboard when a clipboard provider is available.

#### Expand or shrink a selection and copy it to another application

For Wildfire-like syntax-aware expansion:

1. Put the cursor inside the expression and press `<C-Space>` from normal mode.
2. While still in visual mode, repeat `<C-Space>` to select the next parent
   syntax node. Press `<BS>` to return to the previous child node.
3. Type `"+y` while the selection is active to copy it explicitly to the
   terminal/system clipboard. A plain `y` normally does the same because this
   profile enables `clipboard=unnamedplus`.
4. Move to the email or other local application and paste with its normal
   shortcut, usually `Ctrl+V`.

The profile maps these keys to Neovim 0.12's built-in Treesitter selector, so
they do not require an LSP server. The native visual-mode `an` and `in`
mappings remain available as alternatives. If the current filetype has no
parser, Neovim can fall back to an attached LSP selection-range provider. For
delimiter-based selection, use `vi{` or `va{` for braces, `vi(` or `va(` for
parentheses, and `vi[` or `va[` for brackets. `i` excludes delimiters and `a`
includes them. For arbitrary whole lines, press `V`, extend with `j` or `k`,
then `"+y`.

Over SSH, Nvim2 sends the `+` clipboard through OSC 52. Kitty, a compatible
local terminal, and tmux must permit OSC 52 for the final paste to work.
`Ctrl+Shift+C` copies a terminal-emulator selection and is not part of this
Neovim selection workflow.

`<leader>tv` replaces the complete value under the cursor without changing a
register. It handles matching case variants of `true`/`false`, `yes`/`no` and
`on`/`off`, plus lowercase `enable`/`disable` and `enabled`/`disabled`. Unknown
words are left unchanged.

### Comments, spell checking and folds

These are Neovim mappings, not separate plugins.

| Action                           | Keys                                    |
| -------------------------------- | --------------------------------------- |
| Toggle comment on current line   | `gcc`                                   |
| Toggle comment over a motion     | `gc<motion>`, for example `gcap`        |
| Toggle comment on selected lines | `V`, extend the selection, then `gc`    |
| Next or previous misspelling     | `]s`, `[s`                              |
| Suggest spelling corrections     | `z=`                                    |
| Add word to dictionary           | `zg`                                    |
| Mark word as incorrect           | `zw`                                    |
| Toggle fold                      | `za`                                    |
| Open or close fold               | `zo`, `zc`                              |
| Open or close all folds          | `zR`, `zM`                              |
| Move to next or previous fold    | `zj`, `zk`                              |

Spell checking is enabled automatically for Markdown, text, and Git commit
buffers. Supported filetypes use Neovim's native Treesitter fold expression;
folds start open and the normal `z` mappings above control them. Files without
an installed parser retain marker folds (`{{{` and `}}}`). Missing parsers are
installed only by `:Nvim2ToolsInstallSync`, never while opening a file.

## Buffers, windows and terminal mode

### Buffers

| Action                                            | Keys or command                      |
| ------------------------------------------------- | ------------------------------------ |
| Pick an open buffer                               | `<leader><leader>`                   |
| Remove current buffer without breaking the layout | `<C-x>`                              |
| List buffers                                      | `:ls`                                |
| Next or previous buffer                           | `]b`, `[b` or `:bnext`, `:bprevious` |
| Switch by buffer number or name                   | `:buffer <number-or-name>`           |
| Delete current buffer                             | `:bdelete`                           |

`<C-x>` normally decrements a number in stock Neovim. This profile replaces
it with Mini buffer removal.

### Windows and splits

| Action                                     | Keys or command                        |
| ------------------------------------------ | -------------------------------------- |
| Horizontal split                           | `:split` or `<C-w>s`                   |
| Vertical split                             | `:vsplit` or `<C-w>v`                  |
| Focus left, down, up, right split          | `<C-h>`, `<C-j>`, `<C-k>`, `<C-l>`     |
| Return to the previously focused window    | `<C-w>p`                               |
| Close current split                        | `<C-w>c`                               |
| Keep only current split                    | `<C-w>o`                               |
| Make splits equal size                     | `<C-w>=`                               |
| Move split to far left, bottom, top, right | `<C-w>H`, `<C-w>J`, `<C-w>K`, `<C-w>L` |

Splits are automatically resized evenly when the terminal size changes.

### Terminal mode and terminal clipboard

| Action                    | Keys           |
| ------------------------- | -------------- |
| Open a terminal buffer    | `:terminal`    |
| Leave terminal input mode | `<Esc><Esc>`   |
| Copy terminal selection   | `Ctrl+Shift+C` |
| Paste in terminal         | `Ctrl+Shift+V` |

Mouse handling is disabled in Neovim so terminal selection stays under the
terminal emulator's control. Direct SSH sessions use OSC 52 for clipboard
copying. The tmux profile uses `set-clipboard on`, so tmux copy-mode selections
and OSC 52 writes from applications such as Neovim reach the terminal
clipboard. Inside tmux, use `Ctrl+a` then `[`, select with `v`, and copy with
`y`.

## Search and Telescope

| Action                                       | Keys                                  |
| -------------------------------------------- | ------------------------------------- |
| Find files                                   | `<leader>sf`                          |
| Live grep project text                       | `<leader>sg`                          |
| Find files in nearest Git repository         | `<leader>sF`                          |
| Live grep nearest Git repository             | `<leader>sG`                          |
| Search word under cursor or visual selection | `<leader>sw`                          |
| Search current buffer                        | `<leader>/`                           |
| Search text only in open files               | `<leader>s/`                          |
| Search open buffers                          | `<leader><leader>`                    |
| Recent files                                 | `<leader>s.`                          |
| Search diagnostics                           | `<leader>sd`                          |
| Browse quickfix with preview                 | `<leader>sq`                          |
| Browse current location list with preview    | `<leader>sl`                          |
| Browse jump list with preview                | `<leader>sj`, select, then `<Enter>`  |
| Search help                                  | `<leader>sh`                          |
| Search mappings                              | `<leader>sk`                          |
| Search commands                              | `<leader>sc`                          |
| Browse and promote yank history              | `<leader>sy`, select, then `p` or `P` |
| List Telescope pickers                       | `<leader>ss`                          |
| Resume last picker                           | `<leader>sr`                          |
| Search this Neovim configuration             | `<leader>sn`                          |

Common keys inside a Telescope picker:

| Action                          | Insert mode      | Normal mode      |
| ------------------------------- | ---------------- | ---------------- |
| Move to next or previous result | `<C-n>`, `<C-p>` | `j`, `k`         |
| Open result                     | `<CR>`           | `<CR>`           |
| Open in horizontal split        | `<C-x>`          | `<C-x>`          |
| Open in vertical split          | `<C-v>`          | `<C-v>`          |
| Open in a tab                   | `<C-t>`          | `<C-t>`          |
| Scroll preview                  | `<C-d>`, `<C-u>` | `<C-d>`, `<C-u>` |
| Close picker                    | `<Esc>`          | `q`              |
| Show picker mappings            | `<C-/>`          | `?`              |

`<leader>/` searches only the current buffer, so it never searches an entire
workspace. `<leader>sf`, `<leader>sg` and `<leader>sw` use the current working
directory shown by `:pwd`. `<leader>sF` and `<leader>sG` walk upward from the
current file to the nearest `.git` directory and search only that repository;
they fall back to `:pwd` outside Git. This is useful when one Neovim workspace
contains several repositories.

The file and text searches under `<leader>sf`, `<leader>sg`, `<leader>sF` and
`<leader>sG` include hidden files such as `.bashrc`, `.env`, `.github/` and
`.config/`. They still respect `.gitignore`, `.ignore` and global ignore files,
and always exclude `.git/` and `node_modules/`. The command-line
`:Telescope find_files` and `:Telescope live_grep` pickers use the same rules.

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

| Action                                                           | Keys               |
| ---------------------------------------------------------------- | ------------------ |
| Replace quickfix with all currently filtered results and open it | `<C-q>`            |
| Mark or unmark individual results                                | `<Tab>`, `<S-Tab>` |
| Replace quickfix with only explicitly marked results             | `<M-q>` (Alt-q)    |

Both Telescope actions replace the current quickfix list; they do not append
to it. `<M-q>` exports an empty list when no results have been marked with
`<Tab>`. Use `<C-q>` when every currently filtered result is wanted. `<M-q>`
also depends on the terminal correctly sending Alt-modified keys.

Using the resulting quickfix list:

| Action                                                        | Keys or command                      |
| ------------------------------------------------------------- | ------------------------------------ |
| Toggle the quickfix window without clearing its items         | `<leader>tq`                         |
| Open or close the quickfix window directly                    | `:copen`, `:cclose`                  |
| Browse quickfix through Telescope with a file preview         | `<leader>sq`                         |
| Browse the current window's location list with a file preview | `<leader>sl`                         |
| Open the entry under the cursor                               | `<CR>`                               |
| Open the entry in a new split                                 | `<C-w><CR>`                          |
| Alternate between quickfix and the previous code window       | `<C-w>p`                             |
| Next or previous entry                                        | `]q`, `[q` or `:cnext`, `:cprevious` |
| Last or first entry                                           | `]Q`, `[Q` or `:clast`, `:cfirst`    |
| Remove the entry under the cursor from this list              | `dd` in the quickfix window          |
| Run an Ex command for every entry                             | `:cdo {command}`                     |

`dd` only removes the selected location from the current quickfix list. It
does not delete a file, change source code or affect a window-local location
list. Diagnostic `<leader>q` uses a location list instead; open and close that
with `:lopen` and `:lclose`, and navigate it with `]l` and `[l`.

The fastest review flow usually stays in the code window: keep quickfix open
and press `]q` or `[q` to load the next or previous location into that window.
Use `<C-w>p` only when you need to edit the list itself, such as removing an
entry with `dd`, then press `<C-w>p` again to return to code. Use `<leader>sq`
when fuzzy filtering and a preview are more useful than the split list. The
Telescope picker only reads the existing quickfix list; opening it does not
replace or clear the list.

### Find and replace with review

This Telescope plus quickfix workflow is the profile's dependency-free
alternative to Spectre.

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

LuaLS indexes the current workspace, Neovim's own runtime and the explicit
`luv` and `busted` type libraries. It deliberately does not add every installed
plugin repository as a global library. This keeps memory use lower while
preserving completion and navigation for this configuration and Neovim APIs.

### Code navigation and actions

| Action                            | Keys                           |
| --------------------------------- | ------------------------------ |
| Hover documentation               | `K`                            |
| Go to definition with Telescope   | `grd`                          |
| Go to declaration                 | `grD`                          |
| Find references                   | `grr`                          |
| Find implementations              | `gri`                          |
| Go to type definition             | `grt`                          |
| Rename symbol                     | `grn`                          |
| Code action                       | `gra` in normal or visual mode |
| Document symbols                  | `gO`                           |
| Workspace symbols                 | `gW`                           |
| Jump backward after navigation    | `<C-o>`                        |
| Jump forward again                | `<C-i>`                        |
| Return through the tag stack      | `<C-t>`                        |
| Toggle inlay hints when supported | `<leader>th`                   |
| Signature help in insert mode     | `<C-s>` or `<C-k>`             |

Treesitter provides syntax highlighting, indentation, injections, folds and
the `<C-Space>`/`<BS>` selection flow documented above. Native `an` and `in`
only act while already in visual mode; typing normal-mode `a` enters insert
mode. Mini.ai uses `aa` and `ii` for its next-textobject variants. Those are
prefixes rather than standalone normal-mode mappings; for example, `vaa)`
selects around the next parenthesized text and `dii)` deletes inside the next
parenthesized text.

The complete expansion, fallback text-object and external-clipboard workflow is
documented under
[Expand or shrink a selection and copy it to another application](#expand-or-shrink-a-selection-and-copy-it-to-another-application).
After expanding a selection, `d` deletes it into the normal register, `"_d`
deletes without changing registers, and `c` replaces it without changing the
previous yank. Each operator leaves visual mode.

### Diagnostics

| Action                              | Keys                                 |
| ----------------------------------- | ------------------------------------ |
| Next or previous diagnostic         | `]d`, `[d`                           |
| Last or first diagnostic in buffer  | `]D`, `[D`                           |
| Show diagnostic at cursor           | `<C-w>d`                             |
| Put diagnostics in location list    | `<leader>q`                          |
| Search diagnostics with Telescope   | `<leader>sd`                         |
| Next or previous location-list item | `]l`, `[l` or `:lnext`, `:lprevious` |
| Next or previous quickfix item      | `]q`, `[q` or `:cnext`, `:cprevious` |

The diagnostic float opens automatically after jumping with `[d` or `]d`.

### Completion and snippets

| Action                                          | Keys                       |
| ----------------------------------------------- | -------------------------- |
| Open completion or documentation                | `<C-Space>`                |
| Next or previous completion item                | `<C-n>`, `<C-p>` or arrows |
| Accept selected completion                      | `<C-y>`                    |
| Close completion menu                           | `<C-e>`                    |
| Toggle signature help                           | `<C-k>`                    |
| Move forward or backward through snippet fields | `<Tab>`, `<S-Tab>`         |

Blink supplies completion from LSP and paths. LSP-provided snippets can be
accepted with `<C-y>` and are expanded by Neovim's built-in `vim.snippet`
engine. LuaSnip is not installed. The local pairs expand as soon as their
opening delimiter is typed.

The local expansions are defined in `lua/custom/plugins/snippets.lua`. These
five pairs work in every insert-mode buffer:

| Typed | Result |
| ----- | ------ |
| `(`   | `(     | )`  |
| `[`   | `[     | ]`  |
| `{`   | `{     | }`  |
| `'`   | `'     | '`  |
| `"`   | `"     | "`  |

`|` represents the cursor. Press `<Tab>` to leave the pair. These snippets are
not syntax-aware, so they can also expand in comments or other places where a
literal opening character was intended.

These six triggers work only in Markdown buffers:

| Typed   | Expansion                                                                    |
| ------- | ---------------------------------------------------------------------------- |
| ` ``` ` | A three-line fenced block with `lang` selected, followed by an editable body |
| `**`    | `**text**`                                                                   |
| `__`    | `_text_`                                                                     |
| `*_`    | `**_text_**`                                                                 |
| `~~`    | `~~text~~`                                                                   |
| `<<`    | `<https://example.com>`                                                      |

For a fence, type the language over the selected `lang`, press `<Tab>`, and
write the body. For an inline expansion, type its content and press `<Tab>` to
leave it. The expansion does not add surrounding spaces.

## Formatting, linting and tools

The main day-to-day language stacks are:

| Language                            | LSP                        | Formatter                          | Additional diagnostics    |
| ----------------------------------- | -------------------------- | ---------------------------------- | ------------------------- |
| TypeScript, TSX, JavaScript and JSX | TypeScript Language Server | Prettier                           | ESLint through `eslint_d` |
| Python                              | Pyright and Ruff           | Ruff import sorting and formatting | Ruff                      |
| Bash and POSIX shell                | Bash Language Server       | shfmt                              | ShellCheck                |

| Action                                              | Keys or command                 |
| --------------------------------------------------- | ------------------------------- |
| Format buffer or visual selection                   | `<leader>f`                     |
| Toggle format-on-save for this Neovim session       | `<leader>tf` or `:FormatToggle` |
| Disable format-on-save globally                     | `:FormatDisable`                |
| Disable format-on-save for current buffer           | `:FormatDisable!`               |
| Enable format-on-save globally                      | `:FormatEnable`                 |
| Enable format-on-save for current buffer            | `:FormatEnable!`                |
| Inspect formatter selection                         | `:ConformInfo`                  |
| Inspect external tools                              | `:Mason`                        |
| Install all managed tools and parsers synchronously | `:Nvim2ToolsInstallSync`        |

Conform formats configured filetypes on save. `<leader>tf` is useful when one
Neovim process is opened for a repository that should not be reformatted. The
toggle lasts for that process and does not change repository files or settings.
Manual formatting with `<leader>f` remains available while format-on-save is
disabled. Ruff sorts imports and formats Python. `nvim-lint` runs configured
CLI linters after saving; it has no manual mapping. Actionlint runs only for
YAML files under `.github/workflows/`, while yamllint continues to check other
YAML.

Every managed Mason package has an exact version in `lua/custom/lsp.lua`.
`mason-tool-installer.nvim` has both automatic updates and startup installation
disabled. Change a version intentionally, then run `:Nvim2ToolsInstallSync` on
a connected trusted machine to synchronize Mason tools and the configured
Treesitter parsers.

Python uses Pyright for type analysis and Ruff for diagnostics and formatting.
BasedPyright is not installed alongside Pyright because both would publish the
same class of diagnostics. Treat BasedPyright as a replacement: change the
server and pinned Mason package together if its stricter defaults are wanted.
HTML uses the HTML Language Server for completion, hover, symbols and
diagnostics, the HTML Treesitter parser for syntax support and Prettier for
formatting.

TypeScript, TSX, JavaScript and JSX use Prettier for formatting and `eslint_d`
for diagnostics after save. ESLint runs only when the file belongs to a tree
containing `eslint.config.*`, a legacy `.eslintrc*`, or an `eslintConfig`
section in `package.json`. Keep the project's ESLint plugins and parser in its
own `package.json`; Mason supplies the reusable `eslint_d` runner. The
TypeScript Language Server provides completion, hover, navigation, references,
rename, symbols and code actions for TypeScript, TSX, JavaScript and JSX. It
uses the project's TypeScript version when one is installed locally.

For a new TypeScript repository, install the repository's chosen ESLint and
Prettier versions locally and commit its configuration and lockfile. For
example, this records exact current versions rather than ranges:

```bash
npm install --save-dev --save-exact typescript eslint typescript-eslint prettier
```

Use `:ConformInfo` to confirm Prettier selection. Save a file and inspect ESLint
diagnostics with `]d`, `[d` or `<leader>sd`.
Use the normal LSP mappings such as `grd`, `grr`, `gri`, `grn` and `gra`.
`:LspTypescriptSourceAction` offers whole-file actions such as organizing
imports or removing unused code.

## Git and Gitsigns

Gitsigns mappings are buffer-local and appear in files inside a Git working
tree.

| Action                         | Keys                               |
| ------------------------------ | ---------------------------------- |
| Next or previous hunk          | `]c`, `[c`                         |
| Stage hunk                     | `<leader>hs`                       |
| Reset hunk                     | `<leader>hr`                       |
| Stage selected lines           | Select lines, then `<leader>hs`    |
| Reset selected lines           | Select lines, then `<leader>hr`    |
| Stage whole buffer             | `<leader>hS`                       |
| Reset whole buffer             | `<leader>hR`                       |
| Preview hunk                   | `<leader>hp`                       |
| Preview hunk inline            | `<leader>hi`                       |
| Blame current line             | `<leader>hb`                       |
| Diff against index             | `<leader>hd`                       |
| Diff against last commit       | `<leader>hD`                       |
| Current-file hunks in quickfix | `<leader>hq`                       |
| Repository hunks in quickfix   | `<leader>hQ`                       |
| Toggle current-line blame      | `<leader>tb`                       |
| Toggle word-level diff         | `<leader>tw`                       |
| Select current hunk            | `vih` or use `ih` with an operator |

For a quick current-file review, press `]c` to jump to the next changed hunk,
then `<leader>hp` to preview it. Repeat `]c` and `<leader>hp` through the file;
use `[c` to return to the previous hunk. Use `<leader>hq` when you want every
hunk in the current file listed together instead.

## Mini editing modules

### Text objects

Mini.ai extends normal `a` and `i` text objects and searches up to 500 lines.
Examples:

| Action                                       | Keys                       |
| -------------------------------------------- | -------------------------- |
| Select around parentheses                    | `va)`                      |
| Change inside quotes                         | `ci'`                      |
| Yank inside the next quote                   | `yiiq`                     |
| Go to left or right edge of an around-object | `g[<object>`, `g]<object>` |

### Surroundings

| Action                            | Keys                                    |
| --------------------------------- | --------------------------------------- |
| Add surroundings                  | `sa<motion><char>`, for example `saiw)` |
| Add surroundings to selection     | Select text, then `sa<char>`            |
| Delete surroundings               | `sd<char>`, for example `sd'`           |
| Replace surroundings              | `sr<old><new>`, for example `sr)'`      |
| Find surrounding to right or left | `sf<char>`, `sF<char>`                  |
| Highlight surrounding             | `sh<char>`                              |

### Alignment

Mini Align uses plain `g` mappings, not leader mappings. In Normal mode it
acts like an operator, so follow it with a motion or text object. In Visual
mode it operates on the selected lines. It splits each selected line around a
delimiter, pads the resulting fields into columns, and joins them again. It
does not understand the language or replace a formatter.

| Action                                         | Keys or flow                                                              |
| ---------------------------------------------- | ------------------------------------------------------------------------- |
| Align a selected region immediately            | Select it, then `ga<delimiter>`                                           |
| Align a selected region with preview           | Select it, then `gA<delimiter><CR>`                                       |
| Align the current paragraph on `=`             | `gaip=`                                                                   |
| Preview paragraph alignment on `=`             | `gAip=`, then `<CR>` to accept                                            |
| Cancel a preview                               | `<Esc>` or `<C-c>`                                                        |
| Use a multi-character or literal delimiter     | Start `gA` with a region, press `s`, enter the delimiter and press `<CR>` |
| Choose left, center, right or no justification | During preview press `j`, then `l`, `c`, `r` or `n`                       |

For example, line-select these assignments with `V`, press `gA=`, and then
press `<CR>`:

```text
name=alice
long_name=bob
```

The result is:

```text
name      = alice
long_name = bob
```

Use `ga=` instead when the preview is not needed. This is useful for small
assignment tables, Markdown-style text tables, CSV-like text and other local
column layouts. See `:help MiniAlign` for filters and advanced modifiers.

### Split/join

| Action                                                     | Keys or flow                                     |
| ---------------------------------------------------------- | ------------------------------------------------ |
| Toggle the nearest argument list between one line and many | Put the cursor anywhere inside it and press `gS` |
| Toggle a specific region                                   | Select it, then press `gS`                       |
| Repeat the previous split/join elsewhere                   | `.`                                              |

For example, put the cursor anywhere inside this call and press `gS`:

```lua
deploy(image, namespace, timeout)
```

It becomes a multiline argument list. Press `gS` again while inside the same
brackets to join it. The default detection handles comma-separated content in
`()`, `[]` and `{}` and excludes nested brackets and quoted strings. It is
pattern-based rather than syntax-aware, so unusual language constructs can
still need manual formatting. See `:help MiniSplitjoin` for its detection
rules.

### Buffer removal and visited files

| Action                                             | Keys         |
| -------------------------------------------------- | ------------ |
| Remove current buffer                              | `<C-x>`      |
| Select frecent file from current working directory | `<leader>vv` |
| Select frecent file from all tracked directories   | `<leader>vV` |
| Add a label to current file                        | `<leader>va` |
| Remove a label from current file                   | `<leader>vr` |
| Select a label and file from current working directory | `<leader>vl` |
| Select a label and file from all tracked directories   | `<leader>vL` |

Mini Visits records a normal file after it remains open for about one second
and ranks files using both recency and frequency. `<leader>vv` and
`<leader>vl` are scoped to `:pwd`, which initially is the directory where
Neovim was started and can include several repositories in a shared workspace.
They do not replace that scope with the nearest Git root. `<leader>vV` and
`<leader>vL` search the complete history.

To create a persistent project bookmark list, start Neovim from the project or
workspace directory, open each important file, press `<leader>va` and give each
the same label, such as `core`. After restarting Neovim from that directory,
press `<leader>vl`, select `core`, then select a file. `<leader>vr` removes a
label from the current file. Visit history and labels are written to
`~/.local/share/nvim2/mini-visits-index` when Neovim exits. Changing `:pwd`
with `:cd` also changes the scope used by the lowercase pickers.

## Markdown, colors and TODO comments

| Action                                             | Keys or command                        |
| -------------------------------------------------- | -------------------------------------- |
| Toggle Markdown rendering globally                 | `:RenderMarkdown toggle`               |
| Toggle Markdown rendering for current buffer       | `:RenderMarkdown buf_toggle`           |
| Open a side-by-side rendered Markdown preview      | `:RenderMarkdown preview`              |
| Preview the Mermaid fence under the cursor as text | `<leader>ma` or `:MermaidAsciiPreview` |
| Search TODO comments                               | `:TodoTelescope`                       |
| Put TODO comments in quickfix                      | `:TodoQuickFix`                        |

Neovim 0.12 automatically previews color values when an attached language
server supports LSP document colors. The configured Lua, CSS and HTML servers
support them; the TypeScript and Python servers do not.

The Mermaid preview is a local module, not a Neovim plugin or server. Put the
cursor anywhere inside a fenced `mermaid` block and press `<leader>ma`. A
successful render opens a read-only scratch tab. Navigate with the normal
`h`, `j`, `k`, `l`, arrow, `Ctrl-u`, `Ctrl-d`, `gg`, `G`, `zh` and `zl` keys;
press `q` to close it. Horizontal movement is available because wrapping is
disabled.

The renderer is optional. If `mermaid-ascii` is absent, the diagram is empty,
or stable version 1.4.0 does not support that diagram type, Nvim2 shows a
warning and leaves the current window unchanged. The stable renderer is most
useful for flowcharts and sequence diagrams and does not cover all Mermaid
syntax. Render Markdown continues to handle the surrounding Markdown.

Install the pinned x86-64 Linux release in `~/bin` on a connected machine:

```bash
version=1.4.0
asset=mermaid-ascii_Linux_x86_64.tar.gz
expected=a59974c74e3fddfd040f80618a0f7eae535ebe58d91aa1d8d876bc99815dc037
work_dir=$(mktemp -d)
curl -fL \
  "https://github.com/AlexanderGrooff/mermaid-ascii/releases/download/v$version/$asset" \
  -o "$work_dir/$asset"
printf '%s  %s\n' "$expected" "$work_dir/$asset" | sha256sum -c -
tar -xzf "$work_dir/$asset" -C "$work_dir"
mkdir -p "$HOME/bin"
install -m 0755 "$work_dir/mermaid-ascii" "$HOME/bin/mermaid-ascii"
rm -rf "$work_dir"
export PATH="$HOME/bin:$PATH"
mermaid-ascii --help
```

`Nvim2ToolsInstallSync` installs the Mermaid Treesitter parser, but it does not
manage this binary. For a restricted VM, copy the verified
`~/bin/mermaid-ascii` from a compatible connected x86-64 Linux builder. The
binary is statically linked, so no service or runtime package is required.
Run `source ~/.bashrc` before starting Nvim2 if the current shell was opened
before `~/bin` existed.

The old TODO mappings (`]t`, `[t`, `<leader>ft`) have not been restored, and
`<leader>tq` now toggles the quickfix window. Adding TODO mappings requires no
new plugin because `todo-comments.nvim` is already installed. Prefer
`<leader>tn` and `<leader>tp` for TODO navigation: `[t`/`]t` and `[T`/`]T` are
Neovim's built-in tag-list mappings.

## Neo-tree

The visible `>` before tab-indented lines and `·` after trailing spaces come
from Neovim's built-in `listchars`, separately from the `▏` indentation guides.
Hide the built-in whitespace markers temporarily with `:set nolist` and restore
them with `:set list`. Neo-tree draws separate hierarchy lines only inside its
sidebar; `guess-indent.nvim` detects indentation settings but draws no guides.

Neo-tree is enabled through Kickstart's example module. Its common daily keys
are:

| Action in Neo-tree                                 | Keys                              |
| -------------------------------------------------- | --------------------------------- |
| Reveal current file or focus tree                  | `\`                               |
| Open file or expand directory                      | `<CR>` or `<Space>`               |
| Preview file                                       | `P`                               |
| Open in horizontal split, vertical split or tab    | `S`, `s`, `t`                     |
| Close directory or all directories                 | `C`, `z`                          |
| Toggle hidden, dot and Git-ignored items           | `H`                               |
| Fuzzy-find an item or directory                    | `/`, `D`                          |
| Apply a persistent name filter                     | `f`, type the filter, then `<CR>` |
| Clear the active filter                            | `<C-x>`                           |
| Use selected directory as root or go to its parent | `.`, `<BS>`                       |
| Add file or directory                              | `a`, `A`                          |
| Rename, move, copy or delete                       | `r`, `m`, `c`, `d`                |
| Mark for copy or move                              | `y`, `x`                          |
| Paste marked items into selected directory         | `p`                               |
| Clear marked items                                 | `<C-r>`                           |
| Refresh                                            | `R`                               |
| Close tree                                         | `\` or `q`                        |
| Show Neo-tree's authoritative mapping help         | `?`                               |

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
