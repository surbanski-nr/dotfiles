local pairs = require 'custom.plugins.highlight_enclosing_pairs'

local function highlight(window)
  return vim.iter(vim.fn.getmatches(window or 0)):find(function(match) return match.group == 'MatchParen' and match.priority == 9 end)
end

local function move(row, column)
  vim.api.nvim_win_set_cursor(0, { row, column })
  vim.api.nvim_exec_autocmds('CursorMoved', { buffer = 0 })
  return highlight()
end

local function assert_positions(match, opening, closing)
  assert(match, 'enclosing brackets were not highlighted')
  assert(vim.deep_equal(match.pos1, opening), 'wrong opening bracket: ' .. vim.inspect(match.pos1))
  assert(vim.deep_equal(match.pos2, closing), 'wrong closing bracket: ' .. vim.inspect(match.pos2))
end

vim.cmd.enew()
vim.bo.filetype = 'lua'
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  'local outer = {',
  '  inner = {',
  '    first = true,',
  '    second = false,',
  '  },',
  '  last = true,',
  '}',
  'local outside = true',
})
vim.treesitter.start(0, 'lua')
local parser = vim.treesitter.get_parser(0, 'lua')
parser:parse()

local first = move(3, 5)
assert_positions(first, { 2, 11, 1 }, { 5, 3, 1 })
local second = move(4, 5)
assert_positions(second, { 2, 11, 1 }, { 5, 3, 1 })
assert(first.id == second.id, 'moving within the same pair recreated its highlight')

assert_positions(move(6, 3), { 1, 15, 1 }, { 7, 1, 1 })
assert(not move(8, 3), 'enclosing highlight remained after leaving the pair')

move(3, 5)
vim.fn.clearmatches()
assert_positions(move(4, 5), { 2, 11, 1 }, { 5, 3, 1 })

vim.api.nvim_buf_set_lines(0, 4, 4, false, { '    third = true,' })
parser:parse()
assert_positions(move(3, 5), { 2, 11, 1 }, { 6, 3, 1 })

local source_window = vim.api.nvim_get_current_win()
vim.cmd.vsplit()
local split_window = vim.api.nvim_get_current_win()
assert(not highlight(source_window), 'inactive window retained its enclosing highlight')
assert_positions(highlight(), { 2, 11, 1 }, { 6, 3, 1 })
vim.api.nvim_set_current_win(source_window)
assert(not highlight(split_window), 'leaving the split retained its enclosing highlight')
assert_positions(highlight(), { 2, 11, 1 }, { 6, 3, 1 })
vim.api.nvim_win_close(split_window, true)

vim.bo.buftype = 'nofile'
pairs.update()
assert(not highlight(), 'special buffer retained its enclosing highlight')
vim.bo.buftype = ''
assert_positions(move(4, 5), { 2, 11, 1 }, { 6, 3, 1 })

vim.bo.modified = false
vim.cmd.enew()
vim.bo.filetype = 'text'
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'plain (text)' })
assert(not move(1, 8), 'buffer without a parser retained its enclosing highlight')

io.stdout:write 'Nvim2 enclosing pair checks passed\n'
vim.cmd 'qa!'
