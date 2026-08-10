local M = {}

local latest_request = 0

---@param line string
---@return string?, integer?, string?
local function opening_fence(line)
  local indent, marker, info = line:match '^(%s*)(`+)%s*(.-)%s*$'
  if not marker then
    indent, marker, info = line:match '^(%s*)(~+)%s*(.-)%s*$'
  end
  if not marker or #indent > 3 or #marker < 3 then return nil end
  return marker:sub(1, 1), #marker, info
end

---@param line string
---@param marker_char string
---@param minimum_length integer
---@return boolean
local function closing_fence(line, marker_char, minimum_length)
  local pattern = marker_char == '`' and '^(%s*)(`+)%s*$' or '^(%s*)(~+)%s*$'
  local indent, marker = line:match(pattern)
  return marker ~= nil and #indent <= 3 and #marker >= minimum_length
end

---@param info string
---@return boolean
local function is_mermaid(info)
  local language = info:match '^([^%s,{]+)'
  return language ~= nil and language:lower() == 'mermaid'
end

---@class MermaidAsciiBlock
---@field start_line integer
---@field end_line integer
---@field source string

---@param lines string[]
---@param cursor_line integer 1-based line
---@return MermaidAsciiBlock?
function M.find_block(lines, cursor_line)
  local current ---@type { marker_char: string, marker_length: integer, start_line: integer, mermaid: boolean }?

  for line_number, line in ipairs(lines) do
    if current then
      if closing_fence(line, current.marker_char, current.marker_length) then
        if current.mermaid and cursor_line >= current.start_line and cursor_line <= line_number then
          local source = {}
          for index = current.start_line + 1, line_number - 1 do
            source[#source + 1] = lines[index]
          end
          return {
            start_line = current.start_line,
            end_line = line_number,
            source = table.concat(source, '\n'),
          }
        end
        current = nil
      end
    else
      local marker_char, marker_length, info = opening_fence(line)
      if marker_char and marker_length and info then
        current = {
          marker_char = marker_char,
          marker_length = marker_length,
          start_line = line_number,
          mermaid = is_mermaid(info),
        }
      end
    end
  end

  if current and current.mermaid and cursor_line >= current.start_line then
    local source = {}
    for index = current.start_line + 1, #lines do
      source[#source + 1] = lines[index]
    end
    return {
      start_line = current.start_line,
      end_line = #lines,
      source = table.concat(source, '\n'),
    }
  end

  return nil
end

---@param message string
local function warn(message) vim.notify(message, vim.log.levels.WARN, { title = 'Mermaid ASCII' }) end

---@param output string
---@param source_name string
---@param source_line integer
---@param request integer
local function open_preview(output, source_name, source_line, request)
  local lines = vim.split(output:gsub('\n$', ''), '\n', { plain = true })
  if #lines == 0 or (#lines == 1 and lines[1] == '') then
    warn 'mermaid-ascii produced no output'
    return
  end

  vim.cmd.tabnew()
  local buffer = vim.api.nvim_get_current_buf()
  local window = vim.api.nvim_get_current_win()
  vim.api.nvim_buf_set_name(buffer, ('mermaid-ascii://preview/%d'):format(request))
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)

  for option, value in pairs {
    buftype = 'nofile',
    bufhidden = 'wipe',
    buflisted = false,
    swapfile = false,
    modifiable = false,
    readonly = true,
    filetype = 'text',
  } do
    vim.api.nvim_set_option_value(option, value, { buf = buffer })
  end

  for option, value in pairs {
    wrap = false,
    number = false,
    relativenumber = false,
    cursorline = false,
    list = false,
    signcolumn = 'no',
    foldcolumn = '0',
    scrolloff = 0,
    sidescrolloff = 5,
  } do
    vim.api.nvim_set_option_value(option, value, { win = window })
  end

  vim.b[buffer].mermaid_ascii_source = ('%s:%d'):format(source_name, source_line)
  vim.keymap.set('n', 'q', '<Cmd>tabclose<CR>', { buffer = buffer, desc = 'Close Mermaid ASCII preview' })
  vim.cmd 'normal! gg0'
end

---@class MermaidAsciiPreviewOptions
---@field bufnr? integer
---@field cursor_line? integer
---@field executable? string
---@field timeout? integer

---@param opts? MermaidAsciiPreviewOptions
function M.preview(opts)
  opts = opts or {}
  local executable = opts.executable
  if executable == nil then executable = vim.fn.exepath 'mermaid-ascii' end
  if executable == '' then
    warn 'Optional preview unavailable: mermaid-ascii was not found in PATH'
    return
  end

  local buffer = opts.bufnr or vim.api.nvim_get_current_buf()
  local cursor_line = opts.cursor_line or vim.api.nvim_win_get_cursor(0)[1]
  local block = M.find_block(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), cursor_line)
  if not block then
    warn 'Place the cursor inside a fenced mermaid block'
    return
  end
  if block.source:match '^%s*$' then
    warn 'The Mermaid block is empty'
    return
  end

  latest_request = latest_request + 1
  local request = latest_request
  local source_name = vim.api.nvim_buf_get_name(buffer)
  if source_name == '' then source_name = '[No Name]' end

  local ok, error_message = pcall(vim.system, { executable, '-f', '-' }, {
    stdin = block.source .. '\n',
    text = true,
    timeout = opts.timeout or 10000,
  }, function(result)
    vim.schedule(function()
      if request ~= latest_request then return end
      if result.code ~= 0 then
        local detail = vim.trim(result.stderr or '')
        if detail == '' then detail = ('mermaid-ascii exited with status %d'):format(result.code) end
        warn(detail .. '. Use the Mermaid source when this diagram type is unsupported.')
        return
      end
      open_preview(result.stdout or '', vim.fs.basename(source_name), block.start_line, request)
    end)
  end)
  if not ok then warn('Could not start mermaid-ascii: ' .. tostring(error_message)) end
end

vim.api.nvim_create_user_command('MermaidAsciiPreview', function() M.preview() end, {
  desc = 'Preview the Mermaid block under the cursor as Unicode text',
})

vim.keymap.set('n', '<leader>ma', M.preview, { desc = '[M]ermaid [A]SCII preview' })

return M
