local M = {}

local pairs = require 'custom.pairs'
local window_match_variable = 'nvim2_enclosing_pair_match'

M.find = function(bufnr, position) return pairs.find(bufnr, position, pairs.brackets) end

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
