local M = {}

M.brackets = { ['('] = ')', ['['] = ']', ['{'] = '}' }
M.tabout = vim.tbl_extend('force', M.brackets, { ['"'] = '"', ["'"] = "'", ['`'] = '`' })

---@class Nvim2PairRange
---@field open string
---@field close string
---@field start integer[] 0-based row and byte column
---@field finish integer[] 0-based row and byte column

---@param bufnr integer
---@param node TSNode
---@param allowed table<string, string>
---@return Nvim2PairRange?
function M.for_node(bufnr, node, allowed)
  local start_row, start_col, end_row, end_col = node:range()
  if end_col == 0 then return nil end
  local start_line = vim.api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, false)[1]
  local end_line = vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, false)[1]
  if not start_line or not end_line then return nil end

  local opening = start_line:sub(start_col + 1, start_col + 1)
  local closing = end_line:sub(end_col, end_col)
  if allowed[opening] ~= closing then return nil end

  local next_character = start_line:sub(start_col + 2, start_col + 2)
  local previous_character = end_line:sub(end_col - 1, end_col - 1)
  local adjacent_empty_pair = start_row == end_row and end_col - start_col == 2
  if opening == '[' and (next_character == '[' or next_character == '=') then return nil end
  if opening == closing and not adjacent_empty_pair and (next_character == opening or previous_character == closing) then return nil end

  return {
    open = opening,
    close = closing,
    start = { start_row, start_col },
    finish = { end_row, end_col - 1 },
  }
end

---@param bufnr? integer
---@param position? integer[] 0-based row and byte column
---@param allowed? table<string, string>
---@return Nvim2PairRange?
function M.find(bufnr, position, allowed)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not position then
    local cursor = vim.api.nvim_win_get_cursor(0)
    position = { cursor[1] - 1, cursor[2] }
  end

  local line = vim.api.nvim_buf_get_lines(bufnr, position[1], position[1] + 1, false)[1]
  if not line then return nil end
  if #line > 0 then position = { position[1], math.min(position[2], #line - 1) } end

  local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr, pos = position })
  if not ok then return nil end

  while node do
    local pair = M.for_node(bufnr, node, allowed or M.brackets)
    if pair then return pair end
    node = node:parent()
  end
end

return M
