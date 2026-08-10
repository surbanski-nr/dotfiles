local M = {}

local matching_pairs = { ['('] = ')', ['['] = ']', ['{'] = '}' }
local window_match_variable = 'nvim2_enclosing_pair_match'

---@class Nvim2EnclosingPair
---@field open string
---@field close string
---@field start integer[] 0-based row and byte column
---@field finish integer[] 0-based row and byte column

---@param bufnr integer
---@param node TSNode
---@return Nvim2EnclosingPair?
local function pair_for_node(bufnr, node)
  local start_row, start_col, end_row, end_col = node:range()
  local start_line = vim.api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, false)[1]
  local end_line = vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, false)[1]
  if not start_line or not end_line or end_col == 0 then return nil end

  local opening = start_line:sub(start_col + 1, start_col + 1)
  local closing = end_line:sub(end_col, end_col)
  if matching_pairs[opening] ~= closing then return nil end

  return {
    open = opening,
    close = closing,
    start = { start_row, start_col },
    finish = { end_row, end_col - 1 },
  }
end

---@param bufnr? integer
---@param position? integer[] 0-based row and byte column
---@return Nvim2EnclosingPair?
function M.find(bufnr, position)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not position then
    local cursor = vim.api.nvim_win_get_cursor(0)
    position = { cursor[1] - 1, cursor[2] }
  end

  local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr, pos = position })
  if not ok then return nil end

  while node do
    local pair = pair_for_node(bufnr, node)
    if pair then return pair end
    node = node:parent()
  end
end

function M.clear()
  local match_id = vim.w[window_match_variable]
  if type(match_id) == 'number' then pcall(vim.fn.matchdelete, match_id) end
  vim.w[window_match_variable] = nil
end

function M.update()
  M.clear()
  if vim.bo.buftype ~= '' then return end

  local pair = M.find()
  if not pair then return end

  vim.w[window_match_variable] = vim.fn.matchaddpos('MatchParen', {
    { pair.start[1] + 1, pair.start[2] + 1, 1 },
    { pair.finish[1] + 1, pair.finish[2] + 1, 1 },
  }, 9)
end

vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'BufEnter', 'WinEnter' }, {
  desc = 'Highlight the nearest enclosing bracket pair',
  group = vim.api.nvim_create_augroup('nvim2-enclosing-pairs', { clear = true }),
  callback = M.update,
})

vim.api.nvim_create_autocmd('WinLeave', {
  desc = 'Clear the enclosing bracket pair from the inactive window',
  group = 'nvim2-enclosing-pairs',
  callback = M.clear,
})

return M
