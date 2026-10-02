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
| Inspect selection/operator mappings | `:verbose xmap an`, `:verbose omap an` |
| Read help for a key                 | `:help <keys>`                       |
| List commands                       | `<leader>sc`                         |

Which-key also helps discover marks after `'` or a backtick, registers after
`"`, spelling after `z=`, and configured native prefixes such as `g`, `[` and
`]`. Not every native key opens a popup. Use `<leader>sk` and verbose mapping
inspection to distinguish global mappings from buffer-local LSP/picker keys.

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
| Next or previous whitespace-separated WORD | `W`, `B`                            |
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
| Find/move before character backward      | `F<char>`, `T<char>`                  |
| Repeat or reverse character search       | `;`, `,`                              |
| Search forward or backward               | `/text`, `?text`                      |
| Next or previous search match            | `n`, `N`                              |
| Search word under cursor                 | `*` forward, `#` backward             |
| Jump to a visible character in this pane | `<leader>j`, then character and label |
| Clear search highlighting                | `<Esc>`                               |
| Jump backward or forward in jump list    | `<C-o>`, `<C-i>`                      |
| Previous or next edit location           | `g;`, `g,` or `:changes`              |
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

Native `f` and `t` stay on one line. Use `F` and `T` in the reverse direction,
then `;` to repeat in the same direction or `,` to reverse it. For a target
anywhere in the buffer, use `/text<CR>` or `?text<CR>` and repeat with `n` or
`N`. Prefix a literal search with `\V`, for example `/\Vkey[value]<CR>`, so
regular-expression punctuation is treated as text.

`<leader>j` starts Mini Jump2d from Normal mode in the current ordinary editing
pane. Mini Jump is not enabled, and Jump2d's default Enter mapping is disabled.
Type the desired character, then its displayed label when more than one visible target
matches. A single target is selected immediately. `Esc` cancels without moving.
Labels cover visible, unfolded lines only; use native `/` or `?` for the whole
buffer. Neo-tree, pickers, special buffers and other panes are excluded.

`w`/`iw` stop at punctuation, while `W`/`iW` use non-whitespace WORDs. On
`--dry-run` or `/etc/app/config.yaml`, `yiW` copies the whole token, including
punctuation. For wrapped text, `gj`/`gk` move by displayed lines and `g0`/`g$`
reach their displayed edges. `g;`/`g,` revisit edits, unlike the jump list's
navigation locations. Use `q:` or `q/` to edit command or search history in a
normal buffer, then Enter to execute the selected line.

Bundled Matchit extends `%` to supported block keywords, for example Bash
`if`/`else`/`fi`. Its filetype rules are not a universal structural parser;
see `:help matchit`.

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

A short native flow is: use `mA`, `mB` and `mC` in frequently used places,
jump back with `` `A ``, `` `B `` or `` `C ``, and browse them with
`<leader>sm`. Setting the same uppercase mark elsewhere moves it.

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

When a normal file is read, this profile restores the valid `"` mark, which is
the position where that buffer was last exited. The `.` mark is instead the
last change and is not used for startup restoration. An explicit command such
as `nvim +42 file` is applied after the file-read event and remains
authoritative.

`<leader>sm` browses and jumps but does not delete. Note the mark name, close
Telescope, then use `:delmarks {name}`. `:delmarks!` also clears the current
buffer's changelist. Automatic `"` and numbered marks may reappear as Neovim
records later exits; the previous-jump mark `'` is maintained continuously.

Project marks provide a separate persistent, named list per nearest Git
worktree. They do not consume or rewrite native letter marks:

| Action                         | Keys or command                              |
| ------------------------------ | -------------------------------------------- |
| Add or update a named position | `<leader>ma` or `:ProjectMark X`             |
| Pick and jump                  | `<leader>mm`, `<leader>sM`, or `:ProjectMarks` |
| Delete a named position        | `<leader>md` or `:ProjectMarkDelete X`       |

The current buffer must be a normal named file under a Git root. Each nested
repository, clone and worktree has an independent namespace. Records live in
`stdpath('state')/project-marks/` as private JSON files. Their repository path
and file path are canonicalized, so a symlink alias reaches the same marks.
Saved edits before a loaded mark move it with an extmark and persist the new
position only after a successful file save. Discarded edits do not move the
stored position. A missing target is reported as stale and remains deletable.

Moving an entire checkout creates a new namespace. Renames and edits made
while Neovim is closed are not followed automatically, and competing writes
to the same name use the last successful atomic rename. Use the command again
to update a stale position. Mini Visits labels under `<leader>v` remain useful
for frecency and cwd-scoped groups of files.

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
| Adjust the other end of a selection                             | `o` in Visual mode                      |
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

For a rectangular prefix, put the cursor on the first target column, press
`<C-v>`, extend over the rows, press `I`, type the prefix, then press `<Esc>`.
The prefix appears on every selected row after Insert mode ends. To append to
unequal-length lines, select their first column with `<C-v>`, extend over the
rows, press `$`, then `A`, type the suffix and press `<Esc>`. Without `$`, the
append uses one fixed rectangular column.

For example, selecting these lines with `<C-v>jj$A;<Esc>`:

```text
a
longer
xy
```

produces `a;`, `longer;`, and `xy;`. Select rectangular columns and use `"_d`
to delete without replacing the yank register, or `c` to replace the block.
For a Visual Line selection, alternatives are `:'<,'>s/^/prefix/`,
`:'<,'>s/$/suffix/`, and `:'<,'>s/pattern//g`. Use `%s` for the whole buffer
and add the `c` flag when each replacement needs confirmation. Use `grn` when
an attached language server should rename a code symbol semantically. Record
a macro with `q{register}`, perform a repeated multi-step edit, stop with `q`,
and replay with `@{register}` when the change is textual rather than semantic.
See `:help visual-block`, `:help :substitute`, and `:help recording`.

#### Small native editing toolbox

For repeated reviewed text changes, search `/\Vold.name<CR>`, use `cgn`, type
the replacement, and press Esc. Move with `n` when needed and use `.` on the
next intended match. `gn`/`gN` select the next/previous search match, including
the current one when the cursor is inside it. This is textual replacement;
`grn` is a capable LSP server's semantic rename. The profile's black-hole
`c` mapping keeps your earlier yank available.

Use a macro for several operations per target: record with `qa`, stop with
`q`, replay with `@a`, repeat with `@@`, or replay three times with `3@a`.
Check the first replay before applying a count.

These occasional operations need no extra movement/operator plugin:

| Task | Native flow |
| --- | --- |
| Move selected complete lines down one line | `:'<,'>move '>+1` |
| Move selected complete lines up one line | `:'<,'>move '<-2` |
| Sort an unordered selected list | `:'<,'>sort`, or `:'<,'>sort u` for unique lines |
| Increment a number | Normal `<C-a>` |
| Make an increasing sequence from selected numbers | Visual `g<C-a>` |
| Reflow a prose paragraph locally | Set an intentional `textwidth`, then `gwip` |

The move destination must exist. Do not sort ordered Ansible tasks, firewall
rules or arbitrary configuration. Normal `<C-x>` removes a buffer in this
profile, not decrements a number. `gw` reflows text without invoking
`formatprg` or `formatexpr`; `gq` can delegate to those options, including an
attached LSP. Check `:setlocal textwidth? formatexpr? formatprg?` and keep
[Conform's formatting policy](#formatting-linting-and-tools) in mind.

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

These are remapped aliases to native Neovim `van`, `an` and `in`, not a
separate selector engine. An installed parser needs no LSP. Without a parser,
fallback requires an attached server supporting `textDocument/selectionRange`;
without either provider there is no useful syntax expansion.

Native `an`/`in` work in Visual and operator-pending modes, not as standalone
Normal motions. They select parent/child nodes, not simply punctuation in/out.
With the Lua parser and the cursor on `image` in
`deploy(image, namespace, timeout)`, `yan` yanks `image` and `y2an` yanks
`(image, namespace, timeout)`. Shrinking uses native history when still valid,
not an arbitrary earlier selection. In Visual mode, `]n`/`[n` select the
next/previous sibling, and `]N`/`[N` grow across a sibling. Sibling navigation
is Treesitter-only, not an LSP fallback feature.

For counts, use `y2an`, `v2an`, or a count on Visual `<C-Space>` after starting
selection. Avoid counting the initial Normal `<C-Space>`: its `van` alias also
counts `v`, which can reuse the size of a previous Visual selection.

For delimiter-based selection, use `vi{`/`va{`, `vi(`/`va(`, or `vi[`/`va[`.
Counts such as `v2i)` and repeating `i)` in Visual mode expand through nested
parentheses even in stock Neovim. Mini changes some whitespace semantics;
see [Text objects](#text-objects). Use `o` to adjust the other selection end
and `gv` to reselect after leaving Visual mode. For complete lines, use `V`,
extend with `j`/`k`, then `"+y`; for an indentation body, see
[Indentation bodies](#indentation-bodies).

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

| Action                                            | Keys or command                       |
| ------------------------------------------------- | ------------------------------------- |
| Pick an open buffer                               | `<leader><leader>`                    |
| Remove current buffer without breaking the layout | `<C-x>`                               |
| Remove all other listed buffers                   | `<leader>xo` or `:DeleteOtherBuffers` |
| List buffers                                      | `:ls`                                 |
| Next or previous buffer                           | `]b`, `[b` or `:bnext`, `:bprevious`  |
| Switch by buffer number or name                   | `:buffer <number-or-name>`            |
| Delete current buffer                             | `:bdelete`                            |

`<C-x>` normally decrements a number in stock Neovim. This profile replaces
it with Mini buffer removal. `:q` closes the current window, which is a pane
showing a buffer; it does not reliably remove that buffer from `:ls`. Use
`<C-x>` when the buffer itself should be removed while preserving the window
layout.

Mini Bufremove is used through its API without `setup()`. Current-buffer
removal prompts when unsaved changes or a running terminal need attention;
cancel to keep them. Forced removal can discard edits or stop a job.

`<leader>xo` and `:DeleteOtherBuffers` remove every other listed buffer while
keeping the current buffer and window layout. They refuse to remove anything
when another buffer has unsaved changes or is a terminal. Save or close those
buffers first. `:DeleteOtherBuffers!` explicitly discards their changes and
stops their terminal jobs. Use `]b` and `[b` to move through open buffers
directly without opening Telescope.

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

For two-text review, open each text in its intended split and run `:diffthis`
in both windows. Use `]c`/`[c` to navigate differences, `:diffupdate` after
edits, and `:diffoff!` to leave diff mode in all windows. This is native diff,
separate from [Gitsigns' Git comparisons](#git-and-gitsigns).

### Restart and Matrix

Neovim 0.12.5 `:restart` and `ZR` save and restore the current session when
the attached UI supports restart. `:restart!` starts without restoring it.
The default stop command is `:qall`, so modified file contents are not saved
by session persistence and can stop a normal restart. `:set sessionoptions?`
shows which windows, tabs and buffers are serialized. Do not use restart from
a headless client or another UI that cannot take over the replacement process.

Run `:MatrixToggle` or press `<leader>tm` for a temporary Matrix animation over
all ordinary editing panes in the current tab. Neo-tree stays visible, as do
help, terminal, quickfix and picker windows. The active overlay is read-only;
`q`, `<Esc>` or `<leader>tm` closes every overlay and returns focus to the
source pane. `\` runs the normal Neo-tree action from that saved source context
and then adjusts the overlays. Leaving the tab also stops the session.

Matrix uses one roughly 15 FPS timer, bounded ASCII streams and scratch buffers
with no swap or undo history. It preserves source text, cursors, folds and
modified flags. It is a temporary visual effect, not a background wallpaper,
session manager or editing buffer.

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
| Search current document symbols              | `<leader>so`                          |
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
| Switch to picker Normal mode    | `<Esc>`          | Not applicable   |
| Close picker                    | `<C-c>`          | `<Esc>`          |
| Show picker mappings            | `<C-/>`          | `?`              |

Normal `q` is not a picker-close mapping. Use the picker mapping help for
picker-specific actions. `<leader>ss` also discovers less frequent builtins:
`registers`, `command_history` and `search_history`. In `registers`, accepting
an entry pastes it and `<C-e>` edits it. This differs from `<leader>sy`, which
only promotes a yank-ring entry and leaves the buffer unchanged.

`<leader>/` searches only the current buffer, so it never searches an entire
workspace. `<leader>sf`, `<leader>sg` and `<leader>sw` use the current working
directory shown by `:pwd`. `<leader>sF` and `<leader>sG` walk upward from the
current file to the nearest `.git` directory and search only that repository;
they fall back to `:pwd` outside Git. This is useful when one Neovim workspace
contains several repositories.

Neo-tree root changes also affect the tab's cwd under the existing
[cwd binding](#neo-tree). A window-local `:lcd` can override it. Uppercase
Git-root searches and canonical project marks keep their independent scope.

The file and text searches under `<leader>sf`, `<leader>sg`, `<leader>sF` and
`<leader>sG` include hidden files such as `.bashrc`, `.env`, `.github/` and
`.config/`. They still respect `.gitignore`, `.ignore` and global ignore files,
and always exclude `.git/` and `node_modules/`. The command-line
`:Telescope find_files` and `:Telescope live_grep` pickers use the same rules.
Telescope keeps its portable Lua sorter. The separately installed `fzf`
command helps shell workflows but is not Telescope's compiled
`telescope-fzf-native.nvim` extension, which remains intentionally absent to
keep offline builds simple.

### Query operators

The default file and generic Telescope sorters extend the existing Lua fzy
matching with a small query language:

| Query | Meaning |
| --- | --- |
| `foo` | Fuzzy fzy match |
| `foo bar` | Both terms in any order |
| `foo \| bar` | Either adjacent alternative |
| `!test` | Exclude a literal substring |
| `^src/` | Require a literal prefix |
| `.lua$` | Require a literal suffix |
| `^README.md$` | Require literal equality |
| `!^test/`, `!_test.lua$`, `!^README.md$` | Exclude a prefix, suffix, or exact value |

Whitespace-separated groups use AND. A standalone, unescaped `|` joins the
neighboring terms with OR, and OR binds more tightly than AND. For example,
`foo | bar baz` means `(foo OR bar) AND baz`, while
`^src/ .lua$ | .vim$ !test` accepts `src/main.lua` and `src/view.vim` but
rejects test paths. Parentheses are explanatory only and are not query syntax.

Backslash quotes the next character, so `\!note`, `\^draft`, `file\$`, `\|`,
`a\ b`, and `\\` search for those characters without treating them as
operators. A final backslash is literal. Quotes have no grouping role and are
ordinary searchable characters. This makes whitespace different from the old
single-term behavior: an unescaped space is AND, while `a\ b` is one fuzzy
term containing a space.

Matching remains case-insensitive in the same way as Telescope's fzy sorter.
There is no smartcase or additional Unicode normalization. Positive terms use
the original fzy score, OR takes the best accepted alternative, AND adds group
scores, and an accepted negative term contributes a neutral score of 1.
Incomplete operator-only terms and empty OR branches are ignored while typing.
An empty query shows every entry. Queries longer than 1,024 bytes or containing
more than 32 nonempty terms intentionally show no results instead of being
truncated. These are query limits, not candidate limits; long candidate
behavior remains the behavior of the base fzy sorter. Regular expressions,
parentheses, and the rest of the full fzf query language are not supported.

Operators apply to the complete `ordinal` text supplied by each picker. In file
pickers this is normally the path relative to that picker's working directory;
in current-buffer and symbol pickers it includes the text chosen by those
pickers. The adapter is active for file, current-buffer, symbol, and other
pickers that use Telescope's default file or generic sorter factory. A picker
that explicitly chooses another sorter is outside this contract.

Highlighting is only a visual hint. Positive fuzzy terms reuse fzy positions,
and visible literal anchor text is highlighted without reapplying the anchor
to decorated display text. More than one visible OR alternative can therefore
be highlighted. Negative terms and unescaped operator syntax are not
highlighted; a quoted operator character is searchable and may be highlighted.
Shortened or decorated displays may omit a valid match from highlighting.

`live_grep` first asks ripgrep to collect lines for its initial prompt. In
insert mode, press `<C-Space>` to switch that result set to fuzzy refinement;
the local query operators then filter those collected lines. Refinement cannot
find a line that the original ripgrep search did not return.

After a completed native search, a compact current/total label appears at the
end of the active match line. It uses bounded `searchcount()` work and displays
`>999` or `?` rather than claiming an incomplete total is exact. `<leader>tS`
toggles only this label for the session; native highlighting and the statusline
count continue. `<Esc>` clears both search highlighting and the label. The
first version draws one label in the active window only. It does not add a
lens to every match or to live substitutions, and unusual offsets or patterns
may suppress it safely.

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

| Action                                                        | Keys or command                            |
| ------------------------------------------------------------- | ------------------------------------------ |
| Toggle the quickfix window without clearing its items         | `<leader>tq`                               |
| Open or close the quickfix window directly                    | `:copen`, `:cclose`                        |
| Browse quickfix through Telescope with a file preview         | `<leader>sq`                               |
| Browse the current window's location list with a file preview | `<leader>sl`                               |
| Open the entry under the cursor                               | `<CR>`                                     |
| Open the entry in a new split                                 | `<C-w><CR>`                                |
| Alternate between quickfix and the previous code window       | `<C-w>p`                                   |
| Next or previous entry                                        | `]q`, `[q` or `:cnext`, `:cprevious`       |
| Next or previous file represented in quickfix                 | `]<C-q>`, `[<C-q>` or `:cnfile`, `:cpfile` |
| Last or first entry                                           | `]Q`, `[Q` or `:clast`, `:cfirst`          |
| Remove the entry under the cursor from this list              | `dd` in the quickfix window                |
| Run an Ex command for every entry                             | `:cdo {command}`                           |
| Older or newer quickfix list                                  | `:colder`, `:cnewer`                        |

`dd` only removes the selected location from the current quickfix list. It
does not delete a file, change source code or affect a window-local location
list. Diagnostic `<leader>q` uses a location list instead; open and close that
with `:lopen` and `:lclose`, and navigate it with `]l` and `[l`.

To triage captured incident/task output already in quickfix, load the bundled
filter once with `:packadd cfilter`, then use `:Cfilter /ERROR/` to retain
matches or `:Cfilter! /DEBUG/` to exclude them. Filtering creates another list;
`:colder` restores the original and `:cnewer` revisits the filtered list.
This is an opt-in bundled command, not a new installed/startup plugin. Native
`:make` can collect trusted command output when `makeprg` and `errorformat`
match that tool; see `:help quickfix` before adapting a log format.

### Review selected files without returning to quickfix

There is no need to move focus back to the quickfix window between files:

1. In Telescope, mark the files with `<Tab>` and press `<M-q>` to put only
   those files in quickfix. Use `<C-q>` instead when every filtered result is
   wanted.
2. When the quickfix window opens, press `<CR>` on the first file once. Focus
   moves to the editing window.
3. Review or edit the file, then press `]q`. Neovim loads the next quickfix
   entry in the same editing window. Use `[q` to go back.
4. Save each changed buffer with `:update`, or keep moving and run `:wall` once
   after the review.

The quickfix window may remain open or be hidden with `<leader>tq`; navigation
uses the list in either case. Use `<C-w>p` only when the list itself needs an
edit, such as removing an entry with `dd`. No extra mapping is needed because
`]q` and `[q` already provide next and previous navigation from the code
window.

With Telescope `find_files`, each quickfix entry is a file, so `]q` opens the
next selected file. With `live_grep`, entries are individual matches and more
than one may belong to the same file. Use `]<C-q>` or `[<C-q>` when that list
should skip directly to the next or previous distinct file. These are the
built-in mappings for `:cnfile` and `:cpfile`.

Use `<leader>sq` when fuzzy filtering and a preview are more useful than the
split list. The Telescope picker only reads the existing quickfix list;
opening it does not replace or clear the list.

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
| Document symbols in Telescope     | `<leader>so`                   |

Treesitter provides syntax highlighting, indentation, injections and folds.
The `<C-Space>`/`<BS>` selection aliases use native parser/LSP selection.
Native `an`/`in` work in Visual and operator-pending modes; typing Normal `a`
enters Insert mode. Mini.ai reserves `aN`/`iN` for next-object prefixes,
preserving native `an`/`in` and ordinary `aa` arguments. For example, `vaN)`
previews the next parentheses and `diN)` deletes their contents. Preview
uncertain textual matches before destructive edits.

The complete expansion, fallback text-object and external-clipboard workflow is
documented under
[Expand or shrink a selection and copy it to another application](#expand-or-shrink-a-selection-and-copy-it-to-another-application).
After expanding a selection, `d` deletes it into the normal register, `"_d`
deletes without changing registers, and `c` replaces it without changing the
previous yank. Each operator leaves visual mode.

Document symbols describe the current file; workspace symbols can span the
language server's whole workspace. Both depend on server capabilities rather
than textual matches. If no attached server supports document symbols,
`<leader>so` reports that directly. Use `<leader>/` for text in the current
buffer when the target is not an LSP symbol.

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

Fidget displays transient LSP progress. With current defaults,
`progress.display.skip_history=true` and
`notification.override_vim_notify=false`: `:Fidget history` shows only
notifications actually retained by Fidget, not earlier progress or all editor
messages. Use `:messages` for ordinary message history. No notification routing
or progress-history settings are changed here.

### Completion and snippets

| Action                                          | Keys                       |
| ----------------------------------------------- | -------------------------- |
| Open completion or documentation                | `<C-Space>`                |
| Next or previous completion item                | `<C-n>`, `<C-p>` or arrows |
| Accept selected completion                      | `<C-y>`                    |
| Close completion menu                           | `<C-e>`                    |
| Toggle signature help                           | `<C-k>`                    |
| Move through snippet fields or out of a syntax pair | `<Tab>`, `<S-Tab>`      |

Blink's configured sources are `lsp`, `path` and `snippets`, with its portable
Lua matcher. There is no Blink buffer-word source. Native Insert completion
is available separately: `<C-x><C-n>` completes current-buffer words and
`<C-x><C-l>` completes whole lines. These Insert prefixes are unrelated to
Normal `<C-x>` buffer removal. LSP-provided snippets can be
accepted with `<C-y>` and are expanded by Neovim's built-in `vim.snippet`
engine. LuaSnip is not installed. The local pairs expand as soon as their
opening delimiter is typed.

The local expansions are defined in `lua/custom/plugins/snippets.lua`. These
five pairs work in every insert-mode buffer:

| Typed | Result |
| ----- | ------ |
| `(`   | `(CURSOR)`   |
| `[`   | `[CURSOR]`   |
| `{`   | `{CURSOR}`   |
| `'`   | `'CURSOR'`   |
| `"`   | `"CURSOR"`   |

`CURSOR` represents the insertion point and is not inserted. A live snippet
field handles `<Tab>` first. Otherwise, tab-out uses Treesitter to move just
after the nearest unambiguous `()`, `[]`, `{}`, quote or backtick node;
`<S-Tab>` moves just before it. Nested, empty, multi-line and UTF-8 content use
byte-correct syntax ranges. A completion menu, special buffer, missing parser,
incomplete syntax or ambiguous language construct keeps Blink's normal
fallback. Tab-out changes no text or registers.

These local pair expansions are intentionally small and apply in every Insert
mode context. They are not syntax-aware autopairs and do not promise smart
quote handling, paired deletion or closing-character overtyping. The disabled
Kickstart autopairs file is only an upstream example and is not active.

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

GuessIndent detects options, indentation guides only display them, and
Conform actually formats text. To rerun detection use `:GuessIndent`, then
inspect `:setlocal shiftwidth? tabstop? expandtab?`. A project's EditorConfig
settings remain authoritative; detection does not replace formatting or
language validation.

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

Terraform Language Server supplies Terraform navigation and code lenses, but
`terraform fmt` still requires a host `terraform` executable. Ansible Language
Server is managed by Mason and attaches to recognized playbooks; its wider
project features invoke the host `ansible-config` command. Missing host tools
remain visible in `:ConformInfo`, LSP messages and health output.

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

For repository review, run `:Gitsigns diff`, inspect the file panel, and press
`g?` for its mappings. `]f`/`[f` move between reviewed files without returning
focus to the panel. `:Gitsigns show_commit HEAD` reviews the last commit's
changes; `:Gitsigns blame` opens a whole-file blame view. These are already
available commands, not extra mappings or a second Git UI.

Reset (`<leader>hr`/`<leader>hR`) changes working-tree text; unstage changes the
index, not that text. In the diff panel, `s` stages a saved file and `u`
unstages it; directory actions affect listed descendants. Save intended edits
first because panel file-level staging uses saved content. At a hunk,
`stage_hunk` prefers unstaged changes and only unstages a staged hunk when no
unstaged hunk overlaps. The deprecated `undo_stage_hunk` only tracks stages
from this session, so it is not a general unstage recipe.

Treat `<leader>hd` and other index-buffer views carefully: index buffers can
be editable, and writing one changes staging. Revision buffers are read-only;
regular working-tree files remain editable. Read panel help before staging or
resetting, and close a comparison without writing when only reviewing.

## Mini editing modules

### Text objects

Mini.ai extends operator/Visual `a` and `i` text objects. `i` selects inside;
`a` includes a surrounding region. The next-object prefixes are `iN`/`aN`,
leaving native `in`/`an` untouched. Previous-object prefixes remain `il`/`al`.

| Task | Keys |
| --- | --- |
| Copy an argument or its comma-aware around region | `yia`, `yaa` |
| Copy call contents or the whole call | `yif`, `yaf` |
| Copy inside/around any ordinary quote | `yiq`, `yaq`; specific quote: `yi'` |
| Copy inside/around any `()`, `[]` or `{}` pair | `yib`, `yab` |
| Preview a specific bracket region | `vi]`, `va)`, `vi}` |
| Copy tag contents or contents plus tags | `yit`, `yat` |
| Copy the next quote or previous argument | `yiNq`, `yila` |
| Preview around the next/previous bracket object | `vaN)`, `val)` |
| Go to left/right edge of an around-object | `g[<object>`, `g]<object>` |

At `image` in `deploy(image, namespace, timeout)`, `yia` copies `image`,
`yaa` copies `image,`, `yiNa` copies `namespace`, and `yaNa` copies
`, namespace`. At `namespace`, `yila` copies `image`. Use `gS` to
[split/join the same call](#splitjoin), and native
[selection expansion](#expand-or-shrink-a-selection-and-copy-it-to-another-application)
when syntax nodes are a better fit.

These enhancements are not identical to every native delimiter object. On
`(  inner  )`, Mini `yi(` copies `inner`, while `yi)` keeps the edge spaces.
Mini `ib` includes square/curly pairs; stock `ib` is parentheses-only. Mini
`aq` selects the quotes themselves, without stock around-quote whitespace.
Ordinary native objects such as `iw`/`iW` and `ip` still work.

`f` means a function call, not a function definition/body. Most matching is
textual/pattern-based, not query-backed syntax understanding; `n_lines=500`
is a search bound. The default `cover_or_next` search may pick a following
object when none covers the cursor. Preview uncertain regions with `v` before
`d`/`c`. See `:help MiniAi-builtin-textobjects` and `:help MiniAi.config`.

### Indentation bodies

The only additional Mini Extra use is its indentation generator, exposed as
`iI`/`aI` through Mini.ai. It needs no parser, Extra setup, picker or indentation
renderer. Normal `I` and paragraph `ip` keep their meanings.

With the cursor at `api`:

```yaml
service:
  name: api
  replicas: 2
other:
  name: worker
```

Start with `ViIy` to copy the two complete body lines, including indentation,
as a linewise yank. `yiI` is characterwise: it starts with `name: api`
without that first line's two leading spaces; the second line retains them.
`vaI` previews both borders: it includes `service:` and the following
`other:` line. Therefore `daI` is not a safe "delete only this YAML mapping"
shortcut. For an inspected body, `ViI` then `"_d` removes complete body lines
without deleting the sibling header or replacing your yank; `u` restores them.

The helper uses indentation/dedents, not YAML, Python or Ansible semantics.
Blank lines may be included at scope edges; an unclosed scope at end-of-buffer
can be absent, and `cover_or_next` can find a later scope. Inspect every block
before moving/deleting it. See `:help MiniExtra.gen_ai_spec.indent()`.

### Surroundings

| Action                            | Keys                                    |
| --------------------------------- | --------------------------------------- |
| Add surroundings                  | `sa<motion><char>`, for example `saiw)` |
| Add surroundings to selection     | Select text, then `sa<char>`            |
| Delete surroundings               | `sd<char>`, for example `sd'`           |
| Replace surroundings              | `sr<old><new>`, for example `sr)'`      |
| Find surrounding to right or left | `sf<char>`, `sF<char>`                  |
| Highlight surrounding             | `sh<char>`                              |

At `image`, type `saiwf`, enter `wrap`, and press Enter to get `wrap(image)`;
`sdf` unwraps it. `saiwt`, then `job<CR>`, produces `<job>image</job>`.
`saiw(` gives `( image )`, while `saiw)` gives `(image)`. For nested calls,
`2sdf` removes the second enclosing call; `sdnf` targets the next call.
After an ordinary surround change, `.` repeats it elsewhere. For occasional
custom left/right strings, use `?` and its prompts, for example
`saiw?[[<CR>]]<CR>`. See `:help MiniSurround-builtin-surroundings`.

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

For a pipe table, select `name|status` and `api|ready` with `V`, then type
`ga|`; the built-in pipe preset trims fields and aligns columns. In `gA`
preview, `t` trims field whitespace and `i` ignores common unwanted splits
inside quotes/brackets. Inspect the preview rather than treating it as a
language-aware parser. Conform on save can reformat a hand-aligned layout;
use [format controls](#formatting-linting-and-tools) intentionally.

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
still need manual formatting. Visual `gS` limits the operation to that region;
dot-repeat applies the previous split/join operation elsewhere, not arbitrary
semantic restructuring. See `:help MiniSplitjoin` for its detection rules.

### Automatic statusline and icons

Mini Statusline supplies Git/diff, diagnostics, LSP and search sections plus
the custom `current/total:column position` location. Gitsigns provides the
existing Git/diff fallback; Mini Git and Mini Diff are not enabled. Narrow
panes shorten or omit sections, so missing text is not necessarily missing
functionality. Mini Icons is enabled only when the Nerd Font flag is set and
supplies a web-devicons compatibility mock for consumers such as Telescope.
Neither automatic module needs an action key.

### Buffer removal and visited files

| Action                                             | Keys         |
| -------------------------------------------------- | ------------ |
| Remove current buffer                              | `<C-x>`      |
| Remove all other listed buffers                    | `<leader>xo` |
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
`stdpath('state')/mini-visits-index` when Neovim exits, usually
`~/.local/state/nvim2/mini-visits-index` on Linux unless XDG state is overridden.
Changing effective cwd with `:cd`, `:tcd`, `:lcd` or Neo-tree's bound root
changes lowercase picker scope. Labels group files, not named cursor
positions; use [project or native marks](#marks-and-a-small-harpoon-like-shortlist)
for those.

## Markdown, colors and TODO comments

| Action                                             | Keys or command                        |
| -------------------------------------------------- | -------------------------------------- |
| Toggle Markdown rendering globally                 | `:RenderMarkdown toggle`               |
| Toggle Markdown rendering for current buffer       | `:RenderMarkdown buf_toggle`           |
| Open a side-by-side rendered Markdown preview      | `:RenderMarkdown preview`              |
| Preview the Mermaid fence under the cursor as text | `<leader>pm` or `:MermaidAsciiPreview` |
| Search TODO comments                               | `:TodoTelescope`                       |
| Put TODO comments in quickfix                      | `:TodoQuickFix`                        |

Markdown rendering decorates the buffer without changing its source. The
current cursor line is exposed by anti-conceal in Normal mode, while Insert
and Visual editing show source rather than the usual Normal rendering. Use
`buf_toggle` for a plain-source buffer view. Optional render-markdown completion
integrations remain disabled; Blink and native snippets own completion.

Neovim 0.12 automatically previews color values when an attached language
server supports LSP document colors. The configured Lua, CSS and HTML servers
support them; the TypeScript and Python servers do not.

The Mermaid preview is a local module, not a Neovim plugin or server. Put the
cursor anywhere inside a fenced `mermaid` block and press `<leader>pm`. A
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

Use `:TodoTelescope` or `:TodoQuickFix` for comments. `[t`/`]t` and `[T`/`]T`
retain Neovim's native tag-list mappings; no TODO-navigation keys or Mini
Bracketed module are added. `<leader>tq` toggles quickfix.

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
| Show file details                                  | `i`                               |
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

The existing `filesystem.bind_to_cwd=true` is a two-way binding between the
sidebar root and the tab-local cwd. Using `.` or `<BS>` changes that root/cwd;
check `:pwd` back in the editing window before a lowercase Telescope or Visits
search. A window-local `:lcd` can override the tab's cwd. Uppercase
`<leader>sF`/`<leader>sG` still use the current file's nearest Git root (or
effective cwd outside Git), and project marks remain canonical Git-root scoped.
This documents the current policy; it does not decouple or override Neo-tree.

For existing alternative views, use `:Neotree source=buffers` or
`:Neotree source=git_status`, then `?` for that source's actions. These views
do not require another browser plugin.

## Day-to-day development and DevOps recipes

Reuse [format controls and tool ownership](#formatting-linting-and-tools) and
[diagnostics](#diagnostics) with these existing stacks. Exact declarations and
provisioning live in [lua/custom/lsp.lua](lua/custom/lsp.lua),
[lua/custom/conform.lua](lua/custom/conform.lua) and the
[language checks](tests/language_checks.lua), not a second version inventory.

| Workflow | Existing support | Boundary to remember |
| --- | --- | --- |
| YAML, Compose and Helm values | YAML parser/LSP, yamlfmt, yamllint, native/indent selection | Inspect indentation and selected borders before moving blocks |
| Ansible | `yaml.ansible`, AnsibleLS, YAML parser/format/lint | Wider operations need host Ansible commands |
| Helm templates | HelmLS, Helm parser and filetype detection | Templates are not automatically plain-YAML formatting cases |
| Terraform and tfvars | TerraformLS/parser, `terraform fmt`, TFLint | Host Terraform and project context matter |
| Dockerfile | Docker Language Server/parser and Hadolint | No separately configured Dockerfile formatter |
| GitHub Actions | YAML support plus Actionlint under `.github/workflows/` | Actionlint does not run on every YAML file |
| Bash/POSIX shell | BashLS/parser, shfmt, ShellCheck, Matchit | Quote/WORD objects are textual, not safe shell refactoring |
| Markdown runbooks | Rendering, spelling, prose editing, snippets and configured LSP | Rendering is not document conversion |

Useful short flows:

- Copy an expression to a runbook: native `<C-Space>`, expand/shrink to the
  intended node, then `"+y`; see the [clipboard recipe](#expand-or-shrink-a-selection-and-copy-it-to-another-application).
- Edit a call or Terraform expression: preview `via`/`vib` or native nodes,
  change only the intended region, and use `gS` for a comma-separated list.
  Inspect [format selection](#formatting-linting-and-tools) and diagnostics.
- Copy a YAML/Ansible body: `ViI`, inspect the complete selected lines, then
  `y`. Check both source/destination indentation before pasting or moving;
  `aI` includes a following border, not just the owning header.
- Refine a shell flag: `yiW` copies `--dry-run`; `viq` previews a quoted
  value before `c`. ShellCheck and diagnostics still matter after textual edits.
- Triage incident output: search in the buffer or scoped Telescope, export
  chosen locations, and use [quickfix filtering/history](#quickfix-list).
  Review each retained location before `:cdo` edits.
- Review a deployment change: `]c` and `<leader>hp`, then `:Gitsigns diff`
  and panel `g?`; see the [staging/reset warnings](#git-and-gitsigns).
