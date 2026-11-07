local M = {}

function M.inventory(packages_root)
  local inventory = {}
  for _, tool in ipairs(require('custom.lsp').tools) do
    local name = tool[1]
    local path = packages_root .. '/' .. name .. '/mason-receipt.json'
    local file = assert(io.open(path, 'rb'), 'Mason receipt is missing: ' .. name)
    local content = file:read '*a'
    file:close()
    local receipt = vim.json.decode(content)
    local version = assert(receipt.source.id:match '@([^@]+)$', 'Invalid Mason source: ' .. name):gsub('#.*$', '')
    assert(receipt.name == name, 'Mason receipt name mismatch: ' .. name)
    assert(version == tool.version, 'Mason receipt version mismatch: ' .. name)
    local commands = vim.tbl_keys(assert(receipt.links.bin, 'Mason launcher links are missing: ' .. name))
    if name == 'ansible-lint' then vim.list_extend(commands, { 'ansible', 'ansible-config', 'ansible-playbook' }) end
    table.sort(commands)
    inventory[#inventory + 1] = {
      name = name,
      version = version,
      python = receipt.source.id:match '^pkg:pypi/([^@]+)@',
      commands = commands,
    }
  end
  return inventory
end

function M.requirements()
  local required = { rg = true }
  local registry = require 'mason-registry'
  for _, tool in ipairs(require('custom.lsp').tools) do
    local source = registry.get_package(tool[1]).spec.source.id
    if source:match '^pkg:npm/' then required.nodejs = true end
    if source:match '^pkg:pypi/' then required.python = true end
    if source:match '^pkg:golang/' or tool[1] == 'golangci-lint' then required.go = true end
  end
  if require('dap').configurations.python then required.python = true end
  if require('dap').configurations.go then required.go = true end
  if require('custom.lsp').servers.terraformls then required.terraform = true end
  for _, formatters in pairs(require('conform').formatters_by_ft) do
    if vim.tbl_contains(formatters, 'terraform_fmt') then required.terraform = true end
  end
  local result = vim.tbl_keys(required)
  table.sort(result)
  return result
end

function M.check_configuration()
  local registry = require 'mason-registry'
  local refreshed, success = false, false
  registry.refresh(function(ok)
    success = ok
    refreshed = true
  end)
  assert(vim.wait(120000, function() return refreshed end, 100), 'Mason registry refresh timed out')
  assert(success, 'Mason registry refresh failed')
  local selected = {}
  for _, tool in ipairs(require('custom.lsp').tools) do
    selected[tool[1]] = true
  end
  local function need(package, feature)
    assert(selected[package], feature .. ' requires ' .. package .. ' in custom.lsp M.tools; disable the feature or restore the package')
  end
  local mapping = require('mason-lspconfig.mappings').get_mason_map().lspconfig_to_package
  for server in pairs(require('custom.lsp').servers) do
    need(assert(mapping[server], 'No Mason mapping for LSP ' .. server), 'LSP ' .. server)
  end
  if require('custom.lsp').servers.ansiblels then need('ansible-lint', 'Ansible LSP command line tools') end
  local owners = {}
  for _, package in ipairs(registry.get_all_package_specs()) do
    for command in pairs(package.bin or {}) do
      owners[command] = package.name
    end
  end
  local function need_command(command, feature)
    command = vim.fs.basename(command)
    need(assert(owners[command], feature .. ' has no Mason package for command ' .. command), feature)
  end
  local conform = require 'conform'
  for filetype, formatters in pairs(conform.formatters_by_ft) do
    for _, formatter in ipairs(formatters) do
      if formatter ~= 'terraform_fmt' then need_command(conform.get_formatter_info(formatter).command, 'Formatter ' .. formatter .. ' for ' .. filetype) end
    end
  end
  local lint = require 'lint'
  for filetype, linters in pairs(lint.linters_by_ft) do
    for _, linter in ipairs(linters) do
      local command
      if linter == 'golangcilint' then
        command = 'golangci-lint'
      else
        command = lint.linters[linter].cmd
        if type(command) == 'function' then command = command() end
      end
      need_command(command, 'Linter ' .. linter .. ' for ' .. filetype)
    end
  end
  for _, linter in ipairs(require('custom.plugins.lint').workflow_linters) do
    need_command(lint.linters[linter].cmd, 'GitHub workflow linter ' .. linter)
  end
  local dap = require 'dap'
  if dap.configurations.python then need('debugpy', 'Python debugger') end
  if dap.configurations.go then need('delve', 'Go debugger') end
  if #require('custom.treesitter').parsers > 0 then need('tree-sitter-cli', 'Treesitter parser installation') end
  return 'Configured features have their declared Mason packages'
end

return M
