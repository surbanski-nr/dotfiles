local function run()
  assert(vim.api.nvim_get_commands({}).DeleteOtherBuffers, ':DeleteOtherBuffers is unavailable')

  local mapping = vim.fn.maparg('<leader>xo', 'n', false, true)
  assert(type(mapping.callback) == 'function', 'close-other-buffers mapping is unavailable')

  local current = vim.api.nvim_get_current_buf()
  local current_window = vim.api.nvim_get_current_win()
  local clean = vim.api.nvim_create_buf(true, false)
  local modified = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(modified, 0, -1, false, { 'unsaved change' })
  vim.cmd.vsplit()
  local other_window = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(other_window, clean)
  vim.api.nvim_set_current_win(current_window)
  local window_count = #vim.api.nvim_list_wins()

  local messages = {}
  local original_notify = vim.notify
  vim.notify = function(message, level) messages[#messages + 1] = { message = message, level = level } end
  mapping.callback()
  vim.notify = original_notify

  assert(vim.fn.buflisted(clean) == 1, 'clean buffer was removed despite a modified-buffer blocker')
  assert(vim.fn.buflisted(modified) == 1, 'modified buffer was removed without force')
  assert(
    vim.iter(messages):any(function(item) return item.message:find(':DeleteOtherBuffers!', 1, true) ~= nil end),
    'modified-buffer warning did not explain the force option'
  )

  vim.bo[modified].modified = false
  vim.cmd 'DeleteOtherBuffers'
  assert(vim.fn.buflisted(clean) == 0, ':DeleteOtherBuffers kept an unmodified buffer')
  assert(vim.fn.buflisted(modified) == 0, ':DeleteOtherBuffers kept a second unmodified buffer')
  assert(vim.api.nvim_get_current_buf() == current, ':DeleteOtherBuffers changed the current buffer')
  assert(vim.api.nvim_win_is_valid(other_window), ':DeleteOtherBuffers closed a window showing another buffer')
  assert(#vim.api.nvim_list_wins() == window_count, ':DeleteOtherBuffers changed the window layout')

  local forced = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(forced, 0, -1, false, { 'discard me' })
  vim.cmd 'DeleteOtherBuffers!'
  assert(vim.fn.buflisted(forced) == 0, ':DeleteOtherBuffers! kept a modified buffer')
  assert(vim.api.nvim_get_current_buf() == current, ':DeleteOtherBuffers! changed the current buffer')
end

local ok, error_message = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(error_message .. '\n')
  vim.cmd 'cquit 1'
else
  io.stdout:write 'Nvim2 buffer checks passed\n'
  vim.cmd 'qa!'
end
