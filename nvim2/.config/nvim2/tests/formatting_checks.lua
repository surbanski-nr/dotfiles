local root = vim.fn.tempname()
local client_id
vim.fn.mkdir(root, 'p')

local function run()
  local policy = require 'custom.conform'
  local conform = require 'conform'
  local log = root .. '/formatter.log'
  local script = root .. '/formatter.py'
  assert(vim.fn.writefile({}, log) == 0)
  assert(vim.fn.writefile({
    'import sys',
    'from pathlib import Path',
    'with Path(sys.argv[1]).open("a") as log:',
    '    log.write(Path(sys.argv[2]).name + "\\n")',
    'start, end = map(int, sys.argv[3:5]) if len(sys.argv) > 3 else (1, 1000)',
    'for number, line in enumerate(sys.stdin, 1):',
    '    sys.stdout.write(line.replace("=1", " = 1") if start <= number <= end else line)',
  }, script) == 0)
  conform.formatters.formatting_fixture = {
    command = assert(vim.fn.exepath 'python3' ~= '' and vim.fn.exepath 'python3', 'Python is required for the counting formatter'),
    args = { script, log, '$FILENAME' },
    range_args = function(_, context) return { script, log, '$FILENAME', tostring(context.range.start[1]), tostring(context.range['end'][1]) } end,
    stdin = true,
  }
  conform.formatters_by_ft.lua = { 'formatting_fixture' }

  local function keys(sequence) vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(sequence, true, false, true), 'xt', false) end
  local function count() return #vim.fn.readfile(log) end
  local function buffer(name)
    vim.cmd 'enew'
    vim.api.nvim_buf_set_name(0, root .. '/' .. name)
    vim.bo.filetype = 'lua'
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'local a=1', 'local b=1', 'return a+b' })
    return vim.api.nvim_get_current_buf()
  end
  local function edit_save(bufnr)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { 'local a=1' })
    vim.cmd 'silent write'
  end
  local notifications = {}
  vim.notify = function(message) notifications[#notifications + 1] = message end

  local first = buffer 'first.fixture'
  local original = vim.api.nvim_buf_get_lines(first, 0, -1, false)
  vim.cmd 'silent write'
  assert(count() == 0 and vim.deep_equal(vim.fn.readfile(root .. '/first.fixture'), original), 'default save changed formatting')
  assert(#notifications == 0, 'disabled saves must be quiet')
  keys '<leader>f'
  assert(vim.wait(3000, function() return vim.api.nvim_buf_get_lines(first, 0, 1, false)[1] == 'local a = 1' end), 'manual formatting did not complete')
  assert(count() == 1 and vim.deep_equal(vim.fn.readfile(root .. '/first.fixture'), original), 'manual formatting saved the buffer')
  edit_save(first)
  assert(count() == 1 and vim.fn.readfile(root .. '/first.fixture')[1] == 'local a=1', 'manual formatting enabled format on save')
  local second = buffer 'second.fixture'
  vim.cmd 'silent write'
  vim.api.nvim_set_current_buf(first)
  keys '<leader>tf'
  assert(notifications[#notifications] == 'Format on save enabled for this Neovim session', 'toggle notification reported the wrong scope/state')
  vim.api.nvim_buf_set_lines(first, 0, 1, false, { 'local a=1' })
  vim.api.nvim_buf_set_lines(second, 0, 1, false, { 'local a=1' })
  vim.api.nvim_set_current_buf(second)
  vim.cmd 'silent wall'
  local saved = vim.list_slice(vim.fn.readfile(log), 2)
  table.sort(saved)
  assert(count() == 3 and vim.deep_equal(saved, { 'first.fixture', 'second.fixture' }), ':wall did not format both buffers after the session toggle')
  assert(
    vim.fn.readfile(root .. '/first.fixture')[1] == 'local a = 1' and vim.fn.readfile(root .. '/second.fixture')[1] == 'local a = 1',
    ':wall did not save the formatted files'
  )
  local third = buffer 'third.fixture'
  vim.cmd 'silent write'
  assert(count() == 4 and vim.fn.readfile(root .. '/third.fixture')[1] == 'local a = 1', 'new buffers did not inherit the session toggle')
  vim.api.nvim_buf_delete(third, { force = true })
  vim.api.nvim_set_current_buf(first)
  keys '<leader>tf'
  edit_save(first)
  edit_save(second)
  assert(count() == 4, 'session toggle did not disable both buffers')
  keys '<leader>f'
  assert(
    vim.wait(3000, function() return vim.api.nvim_buf_get_lines(second, 0, 1, false)[1] == 'local a = 1' end),
    'manual formatting stopped after the session toggle'
  )
  edit_save(second)
  assert(count() == 5, 'one-time formatting re-enabled format on save')

  vim.api.nvim_set_current_buf(first)
  vim.cmd 'FormatEnable!'
  policy.setup()
  policy.setup()
  conform.formatters_by_ft.lua = { 'formatting_fixture' }
  vim.cmd 'split'
  edit_save(first)
  assert(count() == 6, 'repeated setup lost buffer consent or duplicated save hooks')
  vim.cmd 'close'
  vim.cmd 'FormatDisable'
  edit_save(first)
  edit_save(second)
  assert(count() == 6, 'session disable left a local opt-in active')
  keys '<leader>tf'
  edit_save(first)
  edit_save(second)
  assert(count() == 8, 'session toggle did not enable both buffers')
  vim.cmd 'FormatDisable!'
  edit_save(second)
  assert(count() == 8, 'buffer disable failed under an enabled session default')
  vim.cmd 'FormatEnable'
  edit_save(second)
  assert(count() == 9, 'session enable did not clear a disabled override')
  policy.setup()
  conform.formatters_by_ft.lua = { 'formatting_fixture' }
  edit_save(first)
  assert(count() == 10, 'repeated setup reset the explicit session default')
  vim.cmd 'FormatDisable'

  vim.api.nvim_buf_set_lines(first, 0, -1, false, original)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  keys 'V<leader>f<Esc>'
  assert(
    vim.wait(3000, function() return vim.api.nvim_buf_get_lines(first, 0, 1, false)[1] == 'local a = 1' end),
    'one-time visual formatting did not complete'
  )
  assert(count() == 11 and vim.api.nvim_buf_get_lines(first, 1, 2, false)[1] == 'local b=1', 'visual formatting changed unselected lines')
  vim.cmd 'FormatEnable!'
  vim.bo[first].modified = false
  local name = vim.api.nvim_buf_get_name(first)
  vim.api.nvim_buf_delete(first, { force = true })
  vim.api.nvim_cmd({ cmd = 'edit', args = { name } }, {})
  local reopened = vim.api.nvim_get_current_buf()
  vim.bo.filetype = 'lua'
  edit_save(reopened)
  assert(count() == 11, 'wiping a buffer persisted its opt-in')

  local excluded = buffer 'excluded.fixture'
  vim.bo.filetype = 'helm'
  conform.formatters_by_ft.helm = { 'formatting_fixture' }
  vim.cmd 'FormatEnable!'
  vim.cmd 'silent write'
  assert(count() == 11, 'buffer opt-in added a filetype to the save allowlist')
  vim.bo[excluded].modifiable = false
  keys '<leader>f'
  vim.wait(100)
  assert(count() == 11, 'manual formatting ran on a nonmodifiable buffer')
  vim.bo[excluded].modifiable = true
  vim.bo.filetype = 'formatting-no-formatter'
  keys '<leader>f'
  vim.wait(100)
  assert(count() == 11, 'unsupported filetype unexpectedly ran a formatter')

  local fallback = buffer 'fallback.fixture'
  conform.formatters_by_ft.lua = {}
  local requests, closing, request_id = 0, false, 0
  client_id = vim.lsp.start {
    name = 'nvim2-formatting-fixture',
    cmd = function(dispatchers)
      local function terminate()
        if closing then return end
        closing = true
        dispatchers.on_exit(0, 0)
      end
      return {
        request = function(method, _, callback)
          request_id = request_id + 1
          local id = request_id
          vim.schedule(function()
            if closing then return end
            if method == 'initialize' then
              callback(nil, { capabilities = { documentFormattingProvider = true, positionEncoding = 'utf-16' } })
            elseif method == 'textDocument/formatting' then
              requests = requests + 1
              callback(nil, { { range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 9 } }, newText = 'local a = 1' } })
            else
              callback(nil, nil)
            end
          end)
          return true, id
        end,
        notify = function(method)
          if method == 'exit' then terminate() end
          return true
        end,
        is_closing = function() return closing end,
        terminate = terminate,
      }
    end,
  }
  assert(client_id and vim.wait(3000, function()
    local client = vim.lsp.get_client_by_id(client_id)
    return client and client.initialized and vim.lsp.buf_is_attached(fallback, client_id)
  end), 'formatting LSP fixture did not attach')
  edit_save(fallback)
  assert(requests == 0 and vim.api.nvim_buf_get_lines(fallback, 0, 1, false)[1] == 'local a=1', 'disabled save used LSP formatting')
  keys '<leader>f'
  assert(
    vim.wait(3000, function() return vim.api.nvim_buf_get_lines(fallback, 0, 1, false)[1] == 'local a = 1' end),
    'one-time manual LSP fallback did not format'
  )
  edit_save(fallback)
  assert(requests == 1, 'manual LSP formatting enabled format on save')
  vim.cmd 'FormatEnable!'
  keys '<leader>f'
  assert(
    vim.wait(3000, function() return vim.api.nvim_buf_get_lines(fallback, 0, 1, false)[1] == 'local a = 1' end),
    'enabled manual LSP fallback did not format'
  )
  edit_save(fallback)
  assert(requests == 3, 'enabled save did not use LSP fallback')
  vim.cmd 'FormatDisable!'
  edit_save(fallback)
  assert(requests == 3, 'buffer disable left automatic LSP formatting active')
  keys '<leader>f'
  assert(
    vim.wait(3000, function() return vim.api.nvim_buf_get_lines(fallback, 0, 1, false)[1] == 'local a = 1' end) and requests == 4,
    'buffer disable blocked one-time LSP formatting'
  )

  vim.cmd 'FormatEnable'
  local fresh = root .. '/fresh.lua'
  assert(vim.fn.writefile({
    "local file = vim.fn.tempname() .. '.lua'",
    "local lines = { 'local  value={answer=42}', 'return value' }",
    'assert(vim.fn.writefile(lines, file) == 0)',
    "vim.api.nvim_cmd({ cmd = 'edit', args = { file } }, {})",
    "vim.cmd 'silent write'",
    "assert(vim.deep_equal(vim.fn.readfile(file), lines), 'new process inherited formatting consent')",
    "assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), lines), 'fresh save changed the buffer')",
    'vim.fn.delete(file)',
    "vim.cmd 'qa!'",
  }, fresh) == 0)
  local invocation = '+lua local ok, message = xpcall(function() dofile('
    .. vim.inspect(fresh)
    .. ") end, debug.traceback); if not ok then vim.api.nvim_err_writeln(message); vim.cmd('cquit 1') end"
  local child = vim.system({ vim.v.progpath, '--headless', invocation }, { text = true }):wait(15000)
  assert(child.code == 0, child.stderr)
  print 'Nvim2 formatting checks passed'
end

local ok, message = xpcall(run, debug.traceback)
if client_id then
  local client = vim.lsp.get_client_by_id(client_id)
  if client then client:stop(true) end
end
vim.fn.delete(root, 'rf')
if not ok then
  io.stderr:write(message .. '\n')
  vim.cmd 'cquit 1'
else
  vim.cmd 'qa!'
end
