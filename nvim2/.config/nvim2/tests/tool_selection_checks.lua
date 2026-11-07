local tools = require 'custom.tools'
local lsp = require 'custom.lsp'
local conform = require 'conform'
local lint = require 'lint'
local dap = require 'dap'
local treesitter = require 'custom.treesitter'
local workflows = require 'custom.plugins.lint'

local function fails(callback, message)
  local ok, detail = pcall(callback)
  assert(not ok and tostring(detail):find(message, 1, true), 'Expected failure mentioning ' .. message .. ': ' .. tostring(detail))
end

local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
local function receipt(name, source, commands)
  local path = root .. '/' .. name
  vim.fn.mkdir(path, 'p')
  assert(vim.fn.writefile({ vim.json.encode { name = name, source = { id = source }, links = { bin = commands } } }, path .. '/mason-receipt.json') == 0)
end

local ok, message = xpcall(function()
  lsp.tools = {}
  lsp.servers = {}
  conform.formatters_by_ft = {}
  lint.linters_by_ft = {}
  workflows.workflow_linters = {}
  dap.configurations.python = nil
  dap.configurations.go = nil
  treesitter.parsers = {}
  tools.check_configuration()
  vim.cmd 'Nvim2ToolsInstallSync'
  assert(#tools.inventory(root) == 0 and #lsp.python_inventory(root) == 0 and #lsp.probes() == 0, 'Empty Mason selection retained tools')
  assert(vim.deep_equal(tools.requirements(), { 'rg' }), 'Empty Mason selection retained language runtimes')

  lsp.tools = { { 'stylua', version = 'v2.3.1' } }
  fails(function() tools.inventory(root) end, 'Mason receipt is missing: stylua')
  receipt('stylua', 'pkg:github/johnnymorganz/stylua@v2.3.1', { stylua = 'stylua' })
  receipt('debugpy', 'pkg:pypi/debugpy@1.8.22', { debugpy = 'venv/bin/debugpy', ['debugpy-adapter'] = 'venv/bin/debugpy-adapter' })
  local inventory = tools.inventory(root)
  assert(#inventory == 1 and inventory[1].name == 'stylua' and #lsp.python_inventory(root) == 0, 'Inventory included an unselected Python package')
  assert(#lsp.probes() == 1 and lsp.probes()[1][1] == 'stylua', 'Probes included an unselected executable')
  lsp.tools[1].version = 'v2.3.2'
  fails(function() tools.inventory(root) end, 'Mason receipt version mismatch: stylua')

  lsp.tools = { { 'debugpy', version = '1.8.22' } }
  assert(vim.deep_equal(lsp.python_inventory(root), { { name = 'debugpy', version = '1.8.22' } }), 'Selected Python receipt was omitted')
  assert(vim.deep_equal(tools.requirements(), { 'python', 'rg' }), 'Python package did not require its runtime')
  receipt('different-mason-name', 'pkg:pypi/yamllint@1.38.0', { yamllint = 'venv/bin/yamllint' })
  lsp.tools = { { 'different-mason-name', version = '1.38.0' } }
  assert(vim.deep_equal(lsp.python_inventory(root), { { name = 'yamllint', version = '1.38.0' } }), 'Python inventory assumed the Mason package name')
  lsp.tools = { { 'css-lsp', version = '4.10.0' } }
  assert(vim.deep_equal(tools.requirements(), { 'nodejs', 'rg' }), 'npm package did not require Node.js')
  lsp.tools = { { 'goimports', version = 'v0.51.0' } }
  assert(vim.deep_equal(tools.requirements(), { 'go', 'rg' }), 'Go package did not require the SDK')

  lsp.tools = {}
  lsp.servers.terraformls = {}
  fails(tools.check_configuration, 'terraform-ls')
  lsp.servers = {}
  conform.formatters_by_ft.terraform = { 'terraform_fmt' }
  assert(vim.deep_equal(tools.requirements(), { 'rg', 'terraform' }), 'Terraform formatter did not require Terraform CLI')
  conform.formatters_by_ft = {}
  lint.linters_by_ft.go = { 'golangcilint' }
  fails(tools.check_configuration, 'golangci-lint')
  lint.linters_by_ft = {}
  workflows.workflow_linters = { 'actionlint' }
  fails(tools.check_configuration, 'actionlint')
  workflows.workflow_linters = {}
  dap.configurations.python = { { type = 'python', request = 'launch' } }
  fails(tools.check_configuration, 'debugpy')
  dap.configurations.python = nil
  dap.configurations.go = { { type = 'go', request = 'launch' } }
  fails(tools.check_configuration, 'delve')
  dap.configurations.go = nil
  treesitter.parsers = { 'lua' }
  fails(tools.check_configuration, 'tree-sitter-cli')
  treesitter.parsers = {}

  lsp.tools = { { 'yamlfmt', version = 'v0.21.0' } }
  conform.formatters_by_ft = { yaml = { 'yamlfmt' }, ['yaml.ansible'] = { lsp_format = 'never' } }
  tools.check_configuration()
  vim.bo.filetype = 'yaml.ansible'
  assert(#conform.list_formatters_for_buffer(0) == 0, 'Disabled Ansible formatting inherited the YAML formatter')
  vim.bo.filetype = 'yaml'
  assert(conform.list_formatters_for_buffer(0)[1] == 'yamlfmt', 'Disabling Ansible removed ordinary YAML formatting')
  lsp.tools = {}
  fails(tools.check_configuration, 'yamlfmt')
  conform.formatters.unavailable_fixture = { command = 'dotfiles-no-such-formatter' }
  conform.formatters_by_ft.yaml = { 'unavailable_fixture' }
  assert(not conform.get_formatter_info('unavailable_fixture').available, 'Missing formatter fixture unexpectedly exists')
  local profile = dofile(vim.fn.stdpath 'config' .. '/tests/profile.lua')
  assert(profile.formatter 'unavailable_fixture', 'Missing executable hid an enabled formatter from functional tests')
end, debug.traceback)

vim.fn.delete(root, 'rf')
if not ok then
  io.stderr:write(message .. '\n')
  vim.cmd 'cquit 1'
else
  io.stdout:write 'Nvim2 tool selection checks passed\n'
  vim.cmd 'qa!'
end
