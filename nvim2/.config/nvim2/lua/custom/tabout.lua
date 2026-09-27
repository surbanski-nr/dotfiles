local M = {}

local pairs = require 'custom.pairs'

---@param direction 1|-1
---@return boolean
function M.jump(direction)
  local buffer = vim.api.nvim_get_current_buf()
  if vim.bo[buffer].buftype ~= '' then return false end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local pair = pairs.find(buffer, { cursor[1] - 1, cursor[2] }, pairs.tabout)
  if not pair then return false end

  local destination
  if direction > 0 then
    destination = { pair.finish[1] + 1, pair.finish[2] + 1 }
  else
    destination = { pair.start[1] + 1, pair.start[2] }
  end
  if destination[1] == cursor[1] and destination[2] == cursor[2] then return false end

  return pcall(vim.api.nvim_win_set_cursor, 0, destination)
end

function M.forward() return M.jump(1) end

function M.backward() return M.jump(-1) end

return M
