local M = {}

local namespace = vim.api.nvim_create_namespace 'nvim2-search-lens'
local enabled = true
local pending = false
local state

local function eligible(window, buffer)
  return vim.api.nvim_win_is_valid(window)
    and vim.api.nvim_buf_is_valid(buffer)
    and vim.api.nvim_win_get_buf(window) == buffer
    and vim.bo[buffer].buftype == ''
    and vim.o.hlsearch
    and vim.v.hlsearch == 1
    and vim.fn.getreg '/' ~= ''
end

function M.clear()
  state = nil
  vim.cmd.redraw()
end

function M.refresh()
  pending = false
  state = nil
  if not enabled then return vim.cmd.redraw() end

  local window = vim.api.nvim_get_current_win()
  local buffer = vim.api.nvim_get_current_buf()
  if not eligible(window, buffer) then return vim.cmd.redraw() end

  local ok, count = pcall(vim.fn.searchcount, { recompute = 1, maxcount = 999, timeout = 50 })
  if not ok or type(count) ~= 'table' or count.current == 0 or count.total == 0 then return vim.cmd.redraw() end

  local current = tostring(count.current)
  local total = tostring(count.total)
  if count.incomplete == 1 then
    current = '?'
    total = '?'
  elseif count.incomplete == 2 then
    if count.current > 999 then current = '>999' end
    if count.total > 999 then total = '>999' end
  end
  local cursor = vim.api.nvim_win_get_cursor(window)
  state = {
    win = window,
    buf = buffer,
    row = cursor[1] - 1,
    text = (' %s/%s '):format(current, total),
  }
  vim.cmd.redraw()
end

function M.schedule()
  if pending then return end
  pending = true
  vim.schedule(function()
    if pending then M.refresh() end
  end)
end

function M.toggle()
  enabled = not enabled
  if enabled then
    M.schedule()
  else
    M.clear()
  end
  vim.notify('Search lens: ' .. (enabled and 'on' or 'off'))
end

function M.is_enabled() return enabled end

function M.status() return { enabled = enabled, active = state ~= nil, text = state and state.text or nil, win = state and state.win or nil } end

vim.api.nvim_set_decoration_provider(namespace, {
  on_win = function(_, window, buffer, top, bottom)
    if not enabled or not state or state.win ~= window or state.buf ~= buffer then return false end
    if vim.api.nvim_get_current_win() ~= window or not eligible(window, buffer) then return false end
    if state.row < top or state.row >= bottom then return false end
    vim.api.nvim_buf_set_extmark(buffer, namespace, state.row, 0, {
      ephemeral = true,
      virt_text = { { state.text, 'Nvim2SearchLens' } },
      virt_text_pos = 'eol',
      priority = 180,
    })
  end,
})

vim.api.nvim_create_autocmd({ 'BufEnter', 'CmdlineLeave', 'CursorMoved', 'TextChanged', 'WinEnter', 'WinScrolled' }, {
  desc = 'Refresh the active-window search lens',
  group = vim.api.nvim_create_augroup('nvim2-search-lens', { clear = true }),
  callback = M.schedule,
})

vim.api.nvim_create_autocmd({ 'BufDelete', 'WinClosed' }, {
  desc = 'Clear disposed search-lens state',
  group = 'nvim2-search-lens',
  callback = M.schedule,
})

vim.keymap.set('n', '<Esc>', function()
  vim.cmd.nohlsearch()
  M.clear()
end, { desc = 'Clear search highlighting' })
vim.keymap.set('n', '<leader>tS', M.toggle, { desc = '[T]oggle [S]earch lens' })

return M
