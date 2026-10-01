local M = {}

local namespace = vim.api.nvim_create_namespace 'nvim2-matrix'
local glyphs = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
local session

local function random(state, limit)
  state.seed = (1103515245 * state.seed + 12345) % 2147483648
  return (state.seed % limit) + 1
end

local function streams(state, width, height)
  local result = {}
  for _ = 1, math.max(1, math.min(40, math.floor(width / 8))) do
    result[#result + 1] = {
      column = random(state, math.max(width, 1)) - 1,
      head = -random(state, math.max(height, 1)),
      speed = 4 + random(state, 8),
      tail = 4 + random(state, math.max(2, math.min(7, height))) - 1,
    }
  end
  return result
end

local function stop()
  local current = session
  if not current then return end
  session = nil
  if current.timer then
    current.timer:stop()
    if not current.timer:is_closing() then current.timer:close() end
  end
  pcall(vim.api.nvim_del_augroup_by_id, current.group)
  if vim.api.nvim_win_is_valid(current.win) then pcall(vim.api.nvim_win_close, current.win, true) end
  if vim.api.nvim_buf_is_valid(current.buf) then pcall(vim.api.nvim_buf_delete, current.buf, { force = true }) end
end

M.stop = stop

local function draw(current)
  if session ~= current or not vim.api.nvim_win_is_valid(current.win) then return stop() end
  local width = vim.api.nvim_win_get_width(current.win)
  local height = vim.api.nvim_win_get_height(current.win)
  if width ~= current.width or height ~= current.height then
    current.width = width
    current.height = height
    current.streams = streams(current, width, height)
  end
  local now = vim.uv.hrtime()
  local elapsed = math.min((now - current.last_frame) / 1000000000, 0.25)
  current.last_frame = now
  local rows = {}
  for row = 1, height do
    rows[row] = string.rep(' ', width)
  end
  local highlights = {}
  for _, stream in ipairs(current.streams) do
    stream.head = stream.head + stream.speed * elapsed
    if stream.head - stream.tail > height then
      stream.column = random(current, math.max(width, 1)) - 1
      stream.head = -random(current, math.max(height, 1))
    end
    local head = math.floor(stream.head)
    for offset = 0, stream.tail - 1 do
      local row = head - offset
      if row >= 0 and row < height and stream.column < width then
        local glyph_index = random(current, #glyphs)
        local character = glyphs:sub(glyph_index, glyph_index)
        rows[row + 1] = rows[row + 1]:sub(1, stream.column) .. character .. rows[row + 1]:sub(stream.column + 2)
        local group = offset == 0 and 'Nvim2MatrixHead'
          or offset == 1 and 'Nvim2MatrixBright'
          or offset < math.ceil(stream.tail / 2) and 'Nvim2MatrixMid'
          or 'Nvim2MatrixDim'
        highlights[#highlights + 1] = { row, stream.column, group }
      end
    end
  end
  vim.api.nvim_set_option_value('modifiable', true, { buf = current.buf })
  vim.api.nvim_buf_set_lines(current.buf, 0, -1, false, rows)
  vim.api.nvim_buf_clear_namespace(current.buf, namespace, 0, -1)
  for _, item in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(current.buf, namespace, item[3], item[1], item[2], item[2] + 1)
  end
  vim.api.nvim_set_option_value('modifiable', false, { buf = current.buf })
end

local function start()
  local source = vim.api.nvim_get_current_win()
  if vim.bo[vim.api.nvim_win_get_buf(source)].buftype ~= '' then
    vim.notify('Matrix is available from an ordinary editing window', vim.log.levels.INFO)
    return
  end
  local width = vim.api.nvim_win_get_width(source)
  local height = vim.api.nvim_win_get_height(source)
  local buffer = vim.api.nvim_create_buf(false, true)
  local window = vim.api.nvim_open_win(buffer, true, {
    relative = 'win',
    win = source,
    row = 0,
    col = 0,
    width = width,
    height = height,
    style = 'minimal',
    border = 'none',
  })
  for option, value in pairs {
    buftype = 'nofile',
    bufhidden = 'wipe',
    buflisted = false,
    swapfile = false,
    undolevels = -1,
    filetype = 'nvim2-matrix',
  } do
    vim.api.nvim_set_option_value(option, value, { buf = buffer })
  end
  vim.api.nvim_set_option_value('modifiable', false, { buf = buffer })
  local current = {
    buf = buffer,
    win = window,
    width = width,
    height = height,
    seed = vim.uv.hrtime() % 2147483648,
    last_frame = vim.uv.hrtime(),
  }
  current.streams = streams(current, width, height)
  session = current
  current.group = vim.api.nvim_create_augroup('nvim2-matrix-session', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufLeave', 'WinClosed', 'VimLeavePre' }, {
    group = current.group,
    callback = function() vim.schedule(stop) end,
  })
  vim.keymap.set('n', 'q', stop, { buffer = buffer, nowait = true, desc = 'Close Matrix' })
  vim.keymap.set('n', '<Esc>', stop, { buffer = buffer, nowait = true, desc = 'Close Matrix' })
  vim.keymap.set('n', '<leader>tm', stop, { buffer = buffer, nowait = true, desc = 'Close Matrix' })
  current.timer = vim.uv.new_timer()
  current.timer:start(0, 67, function()
    vim.schedule(function()
      local ok, message = pcall(draw, current)
      if not ok then
        stop()
        vim.notify('Matrix stopped: ' .. tostring(message), vim.log.levels.ERROR)
      end
    end)
  end)
end

function M.toggle()
  if session then
    stop()
  else
    start()
  end
end

function M.status()
  return {
    active = session ~= nil,
    overlays = session and 1 or 0,
    timer = session ~= nil and session.timer ~= nil and not session.timer:is_closing(),
  }
end

vim.api.nvim_create_user_command('MatrixToggle', M.toggle, { desc = 'Toggle Matrix in the current window' })
vim.keymap.set('n', '<leader>tm', M.toggle, { desc = '[T]oggle [M]atrix' })

return M
