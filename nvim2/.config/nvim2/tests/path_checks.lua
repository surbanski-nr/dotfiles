local root = vim.fn.tempname() .. ' home with spaces'
local managed = root .. '/managed/bin/path-probe'

local function executable(path, output)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  assert(vim.fn.writefile({ '#!/usr/bin/env bash', 'printf "' .. output .. '\\n"' }, path) == 0)
  assert(vim.fn.setfperm(path, 'rwxr-xr-x') == 1)
end

for directory, output in pairs { bin = 'home-bin', ['project venv/bin'] = 'venv' } do
  executable(root .. '/' .. directory .. '/path-probe', output)
end
executable(root .. '/bin/unique-user-tool', 'unique')
executable(root .. '/managed/bin/path-probe', 'managed')
local init = root .. '/init.lua'
assert(vim.fn.writefile({
  'vim.opt.runtimepath:prepend(vim.env.TEST_NVIM_CONFIG)',
  "require('custom.lsp').mason.install_root = vim.env.HOME .. '/managed'",
  "require('custom.lsp').mason.registry_cache.refresh = false",
  "dofile(vim.env.TEST_NVIM_CONFIG .. '/init.lua')",
}, init) == 0)
local fixture = root .. '/check.lua'
assert(vim.fn.writefile(
  vim.split(
    [=[
local expected = vim.env.TEST_EXPECTED
assert(vim.fn.exepath('path-probe') == expected, 'Mason startup demoted the selected provider')
local function output(args)
  -- Pipe-based commands must not inherit the caller's controlling terminal.
  local result = vim.system(args, { text = true, detach = true }):wait(10000)
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end
local selected = output { 'path-probe', '--version' }
require('mason').setup(require('custom.lsp').mason)
require('custom.lsp').restore_path()
require('custom.lsp').restore_path()
assert(vim.fn.exepath('path-probe') == expected, 'repeated setup changed selection')
local count = 0
for _, path in ipairs(vim.split(vim.env.PATH, ':', { plain = true })) do
  assert(path ~= '', 'PATH permits implicit current-directory lookup')
  if path == vim.env.HOME .. '/bin' then count = count + 1 end
end
assert(count == tonumber(vim.env.TEST_USER_BIN_COUNT), 'user bin entry was duplicated or retained')
vim.cmd 'enew'
vim.cmd 'terminal path-probe --version'
assert(vim.fn.jobwait({ vim.b.terminal_job_id }, 10000)[1] == 0, 'terminal command failed')
local terminal = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
assert(terminal:find(selected, 1, true), 'terminal selected a different provider')
local shell = output { 'bash', '--noprofile', '--norc', '-ic', 'source "$TEST_BASHRC"; path-probe' }
assert(shell == vim.env.TEST_SHELL_EXPECTED, 'nested Bash lost provider selection')
if count == 1 then
  assert(output { 'unique-user-tool' } == 'unique')
  assert(vim.uv.fs_rename(vim.env.HOME .. '/bin', vim.env.HOME .. '/saved-user-bin'))
  require('custom.lsp').restore_path()
  assert(not vim.env.PATH:find(vim.env.HOME .. '/bin', 1, true), 'deleted user bin survived rebuilding')
  assert(vim.uv.fs_rename(vim.env.HOME .. '/saved-user-bin', vim.env.HOME .. '/bin'))
end
vim.cmd 'qa!'
]=],
    '\n',
    { plain = true }
  ),
  fixture
) == 0)

local bashrc = vim.env.TEST_BASHRC
if not bashrc then
  if vim.env.DOTFILES_OFFLINE_RELEASE_ROOT then
    bashrc = vim.env.DOTFILES_OFFLINE_RELEASE_ROOT .. '/dotfiles/bash/.bashrc'
  else
    local init = vim.fn.resolve(vim.fn.stdpath 'config' .. '/init.lua')
    bashrc = vim.fs.normalize(vim.fs.dirname(init) .. '/../../../bash/.bashrc')
  end
end
assert(vim.fn.filereadable(bashrc) == 1, 'dotfiles Bash configuration is required')
for _, mode in ipairs { 'enabled', 'venv', 'ignored', 'nonexecutable' } do
  local environment = vim.fn.environ()
  -- HOME is a fixture; keep the parent's installed plugins.
  environment.XDG_DATA_HOME = vim.env.XDG_DATA_HOME or vim.fs.dirname(vim.fn.stdpath 'data')
  environment.HOME = root
  environment.PATH = root .. '/bin:' .. root .. '/managed/bin:' .. vim.env.PATH .. '::'
  environment.DOTFILES_IGNORE_USER_BIN = mode == 'ignored' and '1' or ''
  environment.VIRTUAL_ENV = mode == 'venv' and (root .. '/project venv') or ''
  environment.TEST_EXPECTED = mode == 'venv' and (root .. '/project venv/bin/path-probe') or mode == 'enabled' and (root .. '/bin/path-probe') or managed
  environment.TEST_USER_BIN_COUNT = mode == 'ignored' and '0' or '1'
  environment.TEST_SHELL_EXPECTED = (mode == 'ignored' or mode == 'nonexecutable') and 'managed' or mode == 'venv' and 'venv' or 'home-bin'
  environment.TEST_BASHRC = bashrc
  environment.TEST_PATH_FIXTURE = fixture
  environment.TEST_NVIM_CONFIG = vim.fn.stdpath 'config'
  environment.TERM = 'xterm-256color'
  if mode == 'nonexecutable' then assert(vim.fn.setfperm(root .. '/bin/path-probe', 'rw-r--r--') == 1) end
  local invocation =
    "+lua local ok, message = xpcall(function() dofile(vim.env.TEST_PATH_FIXTURE) end, debug.traceback); if not ok then vim.api.nvim_err_writeln(message); vim.cmd('cquit 1') end"
  local result = vim.system({ vim.v.progpath, '--headless', '-u', init, invocation }, { env = environment, text = true }):wait(30000)
  assert(result.code == 0, mode .. ': ' .. (result.stderr or ''))
end
vim.fn.delete(root, 'rf')
print 'Nvim2 PATH checks passed'
vim.cmd 'qa!'
