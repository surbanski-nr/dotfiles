local M = {}

local marker_buffer
local marker_window
local enabled = true
local position

local function close_marker()
  if marker_window and vim.api.nvim_win_is_valid(marker_window) then vim.api.nvim_win_close(marker_window, true) end
  marker_window = nil
  position = nil
end

local function is_source_window(window, buffer) return vim.api.nvim_win_get_config(window).relative == '' and vim.bo[buffer].buftype == '' end

local function get_marker_buffer()
  if marker_buffer and vim.api.nvim_buf_is_valid(marker_buffer) then return marker_buffer end

  marker_buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(marker_buffer, 0, -1, false, { '●' })
  vim.bo[marker_buffer].modifiable = false
  return marker_buffer
end

function M.screen_row(line, line_count, window_height)
  if window_height <= 1 or line_count <= 1 then return 0 end
  local ratio = (line - 1) / (line_count - 1)
  return math.floor(ratio * (window_height - 1) + 0.5)
end

function M.update()
  local source_window = vim.api.nvim_get_current_win()
  local source_buffer = vim.api.nvim_win_get_buf(source_window)
  if not enabled or not is_source_window(source_window, source_buffer) then
    close_marker()
    return
  end

  local window_height = vim.api.nvim_win_get_height(source_window)
  local window_width = vim.api.nvim_win_get_width(source_window)
  local row = M.screen_row(vim.api.nvim_win_get_cursor(source_window)[1], vim.api.nvim_buf_line_count(source_buffer), window_height)
  local next_position = { source_window, row, window_width - 1 }
  if marker_window and vim.api.nvim_win_is_valid(marker_window) and vim.deep_equal(position, next_position) then return end

  local config = {
    relative = 'win',
    win = source_window,
    row = row,
    col = window_width - 1,
    width = 1,
    height = 1,
    style = 'minimal',
    border = 'none',
    focusable = false,
    noautocmd = true,
    zindex = 40,
  }
  if marker_window and vim.api.nvim_win_is_valid(marker_window) then
    vim.api.nvim_win_set_config(marker_window, config)
  else
    marker_window = vim.api.nvim_open_win(get_marker_buffer(), false, config)
    vim.wo[marker_window].winhighlight = 'Normal:CursorLineNr'
  end
  position = next_position
end

function M.toggle()
  enabled = not enabled
  M.update()
  vim.notify('Scroll marker: ' .. (enabled and 'on' or 'off'))
end

vim.api.nvim_create_autocmd({
  'BufEnter',
  'CursorMoved',
  'CursorMovedI',
  'TextChanged',
  'TextChangedI',
  'VimResized',
  'WinEnter',
  'WinResized',
}, {
  desc = 'Update the experimental file-position marker',
  group = vim.api.nvim_create_augroup('nvim2-scroll-marker', { clear = true }),
  callback = M.update,
})

vim.api.nvim_create_user_command('ScrollMarkerToggle', M.toggle, { desc = 'Toggle the experimental file-position marker' })
vim.keymap.set('n', '<leader>ts', M.toggle, { desc = '[T]oggle [S]croll marker' })

M.update()

return M
