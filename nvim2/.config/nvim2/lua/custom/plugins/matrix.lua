local M = {}

local namespace = vim.api.nvim_create_namespace 'nvim2-matrix'
local excluded_filetypes = {
  ['neo-tree'] = true,
  TelescopePrompt = true,
  TelescopeResults = true,
  qf = true,
  help = true,
  terminal = true,
}
local glyphs = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
local session
local next_token = 0

local function eligible(window, tab)
  if not vim.api.nvim_win_is_valid(window) or vim.api.nvim_win_get_tabpage(window) ~= tab then return false end
  if vim.api.nvim_win_get_config(window).relative ~= '' then return false end
  local buffer = vim.api.nvim_win_get_buf(window)
  return vim.bo[buffer].buftype == '' and not excluded_filetypes[vim.bo[buffer].filetype]
end

local function random(state, limit)
  state.seed = (1103515245 * state.seed + 12345) % 2147483648
  return (state.seed % limit) + 1
end

local function configure_buffer(buffer)
  for option, value in pairs {
    buftype = 'nofile',
    bufhidden = 'wipe',
    buflisted = false,
    swapfile = false,
    undolevels = -1,
    modifiable = false,
    readonly = true,
    filetype = 'nvim2-matrix',
  } do
    vim.api.nvim_set_option_value(option, value, { buf = buffer })
  end
end

local function stream_set(state, width, height)
  local count = math.max(1, math.min(40, math.floor(width / 8)))
  local streams = {}
  for _ = 1, count do
    streams[#streams + 1] = {
      column = random(state, math.max(width, 1)) - 1,
      head = -(random(state, math.max(height, 1)) - 1),
      speed = 4 + random(state, 8),
      tail = 4 + random(state, math.max(2, math.min(7, height))) - 1,
    }
  end
  return streams
end

local function close_overlay(overlay)
  if vim.api.nvim_win_is_valid(overlay.win) then pcall(vim.api.nvim_win_close, overlay.win, true) end
  if vim.api.nvim_buf_is_valid(overlay.buf) then pcall(vim.api.nvim_buf_delete, overlay.buf, { force = true }) end
end

local function stop(restore_focus)
  local current = session
  if not current then return end
  session = nil
  if current.timer then
    current.timer:stop()
    if not current.timer:is_closing() then current.timer:close() end
  end
  pcall(vim.api.nvim_del_augroup_by_id, current.group)
  for _, overlay in pairs(current.overlays) do
    close_overlay(overlay)
  end
  if restore_focus ~= false and vim.api.nvim_win_is_valid(current.source_win) then pcall(vim.api.nvim_set_current_win, current.source_win) end
end

function M.stop() stop(true) end

local function tree_action()
  if not session then return end
  local token = session.token
  local source = session.source_win
  if not vim.api.nvim_win_is_valid(source) then return stop(false) end
  session.forwarding_tree_action = true
  vim.api.nvim_set_current_win(source)
  local mapping = vim.fn.maparg('\\', 'n', false, true)
  local ok, message
  if type(mapping.callback) == 'function' then
    ok, message = pcall(mapping.callback)
  elseif type(mapping.rhs) == 'string' and mapping.rhs ~= '' then
    ok, message = pcall(vim.api.nvim_feedkeys, vim.api.nvim_replace_termcodes(mapping.rhs, true, false, true), 'nx', false)
  else
    ok, message = false, 'the source window has no Neo-tree mapping'
  end
  if not ok then
    session.forwarding_tree_action = false
    vim.notify('Could not run Neo-tree from Matrix: ' .. tostring(message), vim.log.levels.ERROR)
  end
  vim.defer_fn(function()
    if session and session.token == token then
      session.forwarding_tree_action = false
      M.reconcile()
      local overlay = session.overlays[source]
      if overlay and vim.api.nvim_win_is_valid(overlay.win) then vim.api.nvim_set_current_win(overlay.win) end
    end
  end, 50)
end

local function create_overlay(current, source)
  local width = vim.api.nvim_win_get_width(source)
  local height = vim.api.nvim_win_get_height(source)
  local buffer = vim.api.nvim_create_buf(false, true)
  configure_buffer(buffer)
  local window = vim.api.nvim_open_win(buffer, false, {
    relative = 'win',
    win = source,
    row = 0,
    col = 0,
    width = width,
    height = height,
    style = 'minimal',
    border = 'none',
    focusable = source == current.source_win,
    zindex = 200,
  })
  vim.api.nvim_set_option_value('wrap', false, { win = window })
  vim.api.nvim_set_option_value('winblend', 0, { win = window })
  vim.keymap.set('n', 'q', M.stop, { buffer = buffer, nowait = true, desc = 'Close Matrix' })
  vim.keymap.set('n', '<Esc>', M.stop, { buffer = buffer, nowait = true, desc = 'Close Matrix' })
  vim.keymap.set('n', '<leader>tm', M.stop, { buffer = buffer, nowait = true, desc = 'Close Matrix' })
  vim.keymap.set('n', '\\', tree_action, { buffer = buffer, nowait = true, desc = 'Toggle Neo-tree behind Matrix' })
  current.overlays[source] = {
    source = source,
    win = window,
    buf = buffer,
    width = width,
    height = height,
    streams = stream_set(current, width, height),
  }
end

function M.reconcile()
  local current = session
  if not current or vim.api.nvim_get_current_tabpage() ~= current.tab then return end

  local sources = {}
  for _, window in ipairs(vim.api.nvim_tabpage_list_wins(current.tab)) do
    if eligible(window, current.tab) then sources[window] = true end
  end
  for source, overlay in pairs(current.overlays) do
    if not sources[source] then
      close_overlay(overlay)
      current.overlays[source] = nil
    end
  end
  for source in pairs(sources) do
    local overlay = current.overlays[source]
    local width = vim.api.nvim_win_get_width(source)
    local height = vim.api.nvim_win_get_height(source)
    if overlay and (not vim.api.nvim_win_is_valid(overlay.win) or not vim.api.nvim_buf_is_valid(overlay.buf)) then
      close_overlay(overlay)
      current.overlays[source] = nil
      overlay = nil
    end
    if not overlay then
      create_overlay(current, source)
    elseif width ~= overlay.width or height ~= overlay.height then
      overlay.width = width
      overlay.height = height
      overlay.streams = stream_set(current, width, height)
      if vim.api.nvim_win_is_valid(overlay.win) then
        vim.api.nvim_win_set_config(overlay.win, { relative = 'win', win = source, row = 0, col = 0, width = width, height = height })
      end
    end
  end
  if not next(current.overlays) then stop(false) end
end

local function draw_overlay(current, overlay, elapsed)
  if not vim.api.nvim_buf_is_valid(overlay.buf) then return end
  local rows = {}
  for row = 1, overlay.height do
    rows[row] = {}
    for column = 1, overlay.width do
      rows[row][column] = ' '
    end
  end
  local highlights = {}
  for _, stream in ipairs(overlay.streams) do
    stream.head = stream.head + stream.speed * elapsed
    if stream.head - stream.tail > overlay.height then
      stream.column = random(current, math.max(overlay.width, 1)) - 1
      stream.head = -random(current, math.max(overlay.height, 1))
      stream.speed = 4 + random(current, 8)
      stream.tail = 4 + random(current, math.max(2, math.min(7, overlay.height))) - 1
    end
    local head = math.floor(stream.head)
    for offset = 0, stream.tail - 1 do
      local row = head - offset
      if row >= 0 and row < overlay.height and stream.column < overlay.width then
        local glyph_index = random(current, #glyphs)
        local character = glyphs:sub(glyph_index, glyph_index)
        rows[row + 1][stream.column + 1] = character
        local group = offset == 0 and 'Nvim2MatrixHead'
          or offset == 1 and 'Nvim2MatrixBright'
          or offset < math.ceil(stream.tail / 2) and 'Nvim2MatrixMid'
          or 'Nvim2MatrixDim'
        highlights[#highlights + 1] = { row, stream.column, group }
      end
    end
  end

  local lines = vim.iter(rows):map(function(row) return table.concat(row) end):totable()
  vim.api.nvim_set_option_value('readonly', false, { buf = overlay.buf })
  vim.api.nvim_set_option_value('modifiable', true, { buf = overlay.buf })
  vim.api.nvim_buf_set_lines(overlay.buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(overlay.buf, namespace, 0, -1)
  for _, item in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(overlay.buf, namespace, item[3], item[1], item[2], item[2] + 1)
  end
  vim.api.nvim_set_option_value('modifiable', false, { buf = overlay.buf })
  vim.api.nvim_set_option_value('readonly', true, { buf = overlay.buf })
end

local function frame(token)
  local current = session
  if not current or current.token ~= token then return end
  current.pending = false
  if current.paused then return end
  local now = vim.uv.hrtime()
  local elapsed = math.min((now - current.last_frame) / 1000000000, 0.25)
  current.last_frame = now
  local ok, message = pcall(function()
    M.reconcile()
    if not session or session.token ~= token then return end
    for _, overlay in pairs(current.overlays) do
      draw_overlay(current, overlay, elapsed)
    end
  end)
  if not ok then
    stop(true)
    vim.notify('Matrix stopped after a rendering error: ' .. tostring(message), vim.log.levels.ERROR)
  end
end

local function start()
  local tab = vim.api.nvim_get_current_tabpage()
  local source = vim.api.nvim_get_current_win()
  if not eligible(source, tab) then
    vim.notify('Matrix is available from an ordinary editing window', vim.log.levels.INFO)
    return
  end

  next_token = next_token + 1
  local current = {
    token = next_token,
    tab = tab,
    source_win = source,
    overlays = {},
    seed = vim.uv.hrtime() % 2147483648,
    last_frame = vim.uv.hrtime(),
    pending = false,
    paused = false,
  }
  session = current
  current.group = vim.api.nvim_create_augroup('nvim2-matrix-session', { clear = true })
  vim.api.nvim_create_autocmd({ 'VimResized', 'WinClosed', 'WinNew' }, {
    group = current.group,
    callback = function()
      vim.schedule(function()
        if session and session.token == current.token then M.reconcile() end
      end)
    end,
  })
  vim.api.nvim_create_autocmd({ 'BufEnter', 'WinEnter' }, {
    group = current.group,
    callback = function()
      vim.schedule(function()
        if not session or session.token ~= current.token or current.forwarding_tree_action then return end
        local active = vim.api.nvim_get_current_win()
        local covered = false
        for _, overlay in pairs(current.overlays) do
          if overlay.win == active then
            covered = true
            break
          end
        end
        if covered or vim.bo[vim.api.nvim_win_get_buf(active)].filetype == 'neo-tree' then return end
        local overlay = current.overlays[active]
        if overlay and vim.api.nvim_win_is_valid(overlay.win) then
          vim.api.nvim_set_current_win(overlay.win)
        else
          stop(false)
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd('TabLeave', { group = current.group, callback = function() stop(false) end })
  vim.api.nvim_create_autocmd('VimLeavePre', { group = current.group, callback = function() stop(false) end })
  vim.api.nvim_create_autocmd('FocusLost', { group = current.group, callback = function() current.paused = true end })
  vim.api.nvim_create_autocmd('FocusGained', {
    group = current.group,
    callback = function()
      current.paused = false
      current.last_frame = vim.uv.hrtime()
    end,
  })

  local ok, message = pcall(M.reconcile)
  if not ok or not session then
    stop(false)
    vim.notify('Could not start Matrix: ' .. tostring(message or 'no eligible windows'), vim.log.levels.ERROR)
    return
  end
  local overlay = current.overlays[source]
  if overlay and vim.api.nvim_win_is_valid(overlay.win) then vim.api.nvim_set_current_win(overlay.win) end

  current.timer = vim.uv.new_timer()
  current.timer:start(0, 67, function()
    if current.pending then return end
    current.pending = true
    vim.schedule(function() frame(current.token) end)
  end)
end

function M.toggle()
  if session then
    stop(true)
  else
    start()
  end
end

function M.status()
  if not session then return { active = false, overlays = 0, timer = false } end
  return { active = true, overlays = vim.tbl_count(session.overlays), timer = session.timer ~= nil and not session.timer:is_closing() }
end

vim.api.nvim_create_user_command('MatrixToggle', M.toggle, { desc = 'Toggle Matrix over editing windows in this tab' })
vim.keymap.set('n', '<leader>tm', M.toggle, { desc = '[T]oggle [M]atrix' })

return M
