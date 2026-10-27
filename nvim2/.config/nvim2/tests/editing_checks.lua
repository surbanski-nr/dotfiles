local api = vim.api

local function feed(keys) api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true), 'xt', false) end

local function buffer(lines)
  feed '<Esc>'
  local bufnr = api.nvim_create_buf(true, false)
  api.nvim_set_current_buf(bufnr)
  vim.bo.undolevels = -1
  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo.undolevels = 1000
  vim.bo.modified = false
  vim.bo.expandtab = true
  vim.bo.shiftwidth = 2
  vim.bo.indentexpr = ''
  return bufnr
end

local function expect_lines(expected)
  local actual = api.nvim_buf_get_lines(0, 0, -1, false)
  assert(vim.deep_equal(actual, expected), 'unexpected buffer content: ' .. vim.inspect(actual))
end

local function visible_diagnostic(bufnr, message)
  for _, mark in ipairs(api.nvim_buf_get_extmarks(bufnr, -1, 0, -1, { details = true })) do
    for _, chunk in ipairs(mark[4].virt_text or {}) do
      if chunk[1]:find(message, 1, true) then return true end
    end
  end
  return false
end

local function run()
  local clipboard = {}
  local function copy(lines, regtype) clipboard = { lines, regtype } end
  vim.g.clipboard = {
    name = 'Editing check clipboard',
    copy = { ['+'] = copy, ['*'] = copy },
    paste = { ['+'] = function() return clipboard end, ['*'] = function() return clipboard end },
    cache_enabled = 0,
  }

  buffer { 'first', 'second', 'last' }
  feed 'Vj>'
  expect_lines { '  first', '  second', 'last' }
  assert(vim.fn.mode() == 'V', 'indent ended the linewise selection')
  feed '>'
  expect_lines { '    first', '    second', 'last' }
  feed '<'
  expect_lines { '  first', '  second', 'last' }
  assert(vim.fn.mode() == 'V', 'unindent ended the linewise selection')
  feed '<Esc>u'
  expect_lines { '    first', '    second', 'last' }
  feed 'u'
  expect_lines { '  first', '  second', 'last' }
  feed 'u'
  expect_lines { 'first', 'second', 'last' }
  feed 'G>>'
  expect_lines { 'first', 'second', '  last' }
  assert(vim.fn.mode() == 'n', 'normal indentation entered Visual mode')

  local original = { 'first', 'moving', 'third', 'fourth', 'last' }
  buffer(original)
  feed 'yyj'
  local registers = {}
  for _, register in ipairs { '"', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' } do
    registers[register] = vim.fn.getreginfo(register)
  end
  feed '2<M-j>'
  expect_lines { 'first', 'third', 'fourth', 'moving', 'last' }
  feed '<M-k>'
  expect_lines { 'first', 'third', 'moving', 'fourth', 'last' }
  for register, value in pairs(registers) do
    local actual = vim.fn.getreginfo(register)
    assert(vim.deep_equal(actual, value), ('move changed register %s: %s -> %s'):format(register, vim.inspect(value), vim.inspect(actual)))
  end
  feed 'u'
  expect_lines(original)
  feed 'gg<M-k>'
  expect_lines(original)
  feed 'G<M-j>'
  expect_lines(original)
  feed 'yy'
  assert(vim.fn.getreg '1' == 'last\n', 'a user yank after moving did not enter the yank history')

  buffer { 'first', 'one', 'two', 'after', 'last' }
  feed 'jVj<M-j>'
  expect_lines { 'first', 'after', 'one', 'two', 'last' }
  assert(vim.fn.mode() == 'V', 'move ended the linewise selection')
  feed '<M-j>'
  expect_lines { 'first', 'after', 'last', 'one', 'two' }
  feed '<M-j>'
  expect_lines { 'first', 'after', 'last', 'one', 'two' }
  feed '<Esc>u'
  expect_lines { 'first', 'one', 'two', 'after', 'last' }

  vim.cmd 'only'
  vim.cmd 'vsplit'
  api.nvim_win_set_width(0, 24)
  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.signcolumn = 'no'
  vim.wo.foldcolumn = '0'
  vim.wo.showbreak = ''
  vim.wo.breakindent = false
  local sentence = 'one two threeverylongword four five six seven'
  for _, filetype in ipairs { 'markdown', 'text', 'gitcommit' } do
    buffer { sentence }
    vim.bo.filetype = filetype
    feed '0g$'
    assert(api.nvim_win_get_cursor(0)[2] == 7, filetype .. ' wrapped inside a word')
    expect_lines { sentence }
    assert(not vim.bo.modified, 'display wrapping changed the buffer')
  end
  buffer { sentence }
  vim.bo.filetype = 'lua'
  feed '0g$'
  assert(api.nvim_win_get_cursor(0)[2] > 7, 'prose wrapping leaked into a code buffer')
  vim.cmd 'only'

  buffer { 'unchanged' }
  local path = vim.fn.tempname() .. " file's name.txt"
  api.nvim_buf_set_name(0, path)
  feed '<leader>yp'
  assert(vim.fn.getreg '+' == path, 'file-path shortcut did not copy the absolute path')
  expect_lines { 'unchanged' }
  assert(not vim.bo.modified, 'copying a path modified the buffer')
  buffer { 'unnamed' }
  feed '<leader>yp'
  assert(vim.fn.getreg '+' == path, 'unnamed buffer replaced the clipboard')
  buffer { 'scratch' }
  api.nvim_buf_set_name(0, 'scratch://editing-check')
  vim.bo.buftype = 'nofile'
  feed '<leader>yp'
  assert(vim.fn.getreg '+' == path, 'special buffer replaced the clipboard')

  local namespace = api.nvim_create_namespace 'editing-check-diagnostics'
  local first = buffer { 'first buffer' }
  local second = buffer { 'second buffer' }
  local options = { virtual_text = true, virtual_lines = false, signs = false, underline = false }
  vim.diagnostic.config(options, namespace)
  local function diagnostic(bufnr, message)
    vim.diagnostic.set(namespace, bufnr, { { lnum = 0, col = 0, message = message, severity = vim.diagnostic.severity.ERROR } })
  end
  diagnostic(first, 'first error')
  diagnostic(second, 'second error')
  assert(visible_diagnostic(first, 'first error') and visible_diagnostic(second, 'second error'), 'initial diagnostics were not visible')
  api.nvim_set_current_buf(first)
  feed '<leader>td'
  assert(not visible_diagnostic(first, 'first error'), 'toggle did not hide buffer diagnostics')
  assert(visible_diagnostic(second, 'second error'), 'toggle hid another buffer diagnostics')
  diagnostic(first, 'updated error')
  assert(vim.diagnostic.get(first)[1].message == 'updated error', 'hidden diagnostics stopped updating')
  assert(not visible_diagnostic(first, 'updated error'), 'an update made hidden diagnostics visible')
  feed '<leader>td'
  assert(visible_diagnostic(first, 'updated error'), 'toggle did not restore updated diagnostics')
  assert(visible_diagnostic(second, 'second error'), 'restoring diagnostics changed another buffer')
  vim.diagnostic.reset(namespace)
end

local ok, message = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(message .. '\n')
  vim.cmd 'cquit 1'
else
  io.stdout:write 'Nvim2 editing checks passed\n'
  vim.cmd 'qa!'
end
