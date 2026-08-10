local M = {}

local function add_check(results, name, callback)
  local ok, detail = pcall(callback)
  table.insert(results, {
    name = name,
    ok = ok and detail ~= false,
    detail = ok and detail or tostring(detail),
  })
end

local function check_plugin_lock()
  local lock_path = vim.fs.joinpath(vim.fn.stdpath 'config', 'nvim-pack-lock.json')
  local lock = vim.json.decode(table.concat(vim.fn.readfile(lock_path), '\n'))
  assert(type(lock) == 'table' and type(lock.plugins) == 'table', 'invalid nvim-pack-lock.json')

  local active = {}
  for _, plugin in ipairs(vim.pack.get(nil, { info = false })) do
    assert(plugin.spec and plugin.spec.name, 'vim.pack returned a plugin without a name')
    active[plugin.spec.name] = plugin
  end

  local locked_count = 0
  for name, expected in pairs(lock.plugins) do
    locked_count = locked_count + 1
    local plugin = active[name]
    assert(plugin, ('locked plugin is not active: %s'):format(name))
    assert(plugin.rev == expected.rev, ('plugin revision mismatch: %s'):format(name))
  end

  local active_count = 0
  for name in pairs(active) do
    active_count = active_count + 1
    assert(lock.plugins[name], ('active plugin is absent from lockfile: %s'):format(name))
  end
  assert(active_count == locked_count, ('active/locked plugin count differs: %d/%d'):format(active_count, locked_count))

  return ('%d plugins match nvim-pack-lock.json'):format(active_count)
end

local function check_custom_modules()
  local plugins_dir = vim.fs.joinpath(vim.fn.stdpath 'config', 'lua', 'custom', 'plugins')
  local _, broken_links = require('custom.plugin_loader').scan(plugins_dir)
  assert(#broken_links == 0, 'broken custom plugin symlink: ' .. table.concat(broken_links, ', '))

  local modules = {
    'custom.plugins.default_colors',
    'custom.plugins.enclosing_pairs',
    'custom.plugins.gitsigns',
    'custom.plugins.highlight_colors',
    'custom.plugins.indent_guides',
    'custom.plugins.line_numbers',
    'custom.plugins.lint',
    'custom.plugins.mermaid_ascii',
    'custom.plugins.mini',
    'custom.plugins.native_folds',
    'custom.plugins.neo_tree',
    'custom.plugins.render_markdown',
    'custom.plugins.self_check',
    'custom.plugins.telescope_search',
    'custom.plugins.toggle_values',
    'custom.plugins.which_key',
  }
  for _, module in ipairs(modules) do
    assert(package.loaded[module], ('custom module was not loaded: %s'):format(module))
  end
  return ('%d custom modules loaded'):format(#modules)
end

local function check_plugin_apis()
  local modules = {
    'blink.cmp',
    'conform',
    'gitsigns',
    'ibl',
    'lint',
    'luasnip',
    'mini.visits',
    'neo-tree',
    'render-markdown',
    'telescope.builtin',
    'which-key',
  }
  for _, module in ipairs(modules) do
    assert(require(module), ('plugin API is unavailable: %s'):format(module))
  end
  return ('%d plugin APIs available'):format(#modules)
end

local function check_mappings()
  local mappings = {
    { 'n', '\\' },
    { 'n', 'dd' },
    { 'n', 'ga' },
    { 'n', 'gA' },
    { 'n', 'gS' },
    { 'n', '<leader>/' },
    { 'n', '<leader>ma' },
    { 'n', '<leader>sF' },
    { 'n', '<leader>sG' },
    { 'n', '<leader>sf' },
    { 'n', '<leader>sg' },
    { 'n', '<leader>sm' },
    { 'n', '<leader>tc' },
    { 'n', '<leader>tf' },
    { 'n', '<leader>ti' },
    { 'n', '<leader>tl' },
    { 'n', '<leader>tv' },
    { 'n', '<leader>vv' },
    { 'n', '<leader>vV' },
  }
  for _, mapping in ipairs(mappings) do
    assert(vim.fn.maparg(mapping[2], mapping[1]) ~= '', ('missing %s-mode mapping: %s'):format(mapping[1], mapping[2]))
  end
  assert(vim.fn.maparg('dd', 'n') == [["_dd]], 'dd no longer uses the black-hole register')
  return ('%d core mappings available'):format(#mappings)
end

local function check_commands()
  local commands = vim.api.nvim_get_commands {}
  local expected = {
    'ConformInfo',
    'FormatDisable',
    'FormatEnable',
    'FormatToggle',
    'IBLToggle',
    'Mason',
    'MermaidAsciiPreview',
    'Neotree',
    'Nvim2Check',
    'Nvim2ToolsInstallSync',
    'RenderMarkdown',
    'TodoTelescope',
  }
  for _, command in ipairs(expected) do
    assert(commands[command], ('missing command: %s'):format(command))
  end
  return ('%d commands available'):format(#expected)
end

local function check_options()
  assert(vim.g.have_nerd_font == true, 'Nerd Font support is disabled')
  assert(vim.o.relativenumber, 'relative line numbers are disabled')
  assert(vim.o.mouse == '', 'mouse should be controlled by the terminal')
  assert(vim.o.winborder == 'rounded', 'default window border is not rounded')
  assert(vim.o.scrolloff == 15, 'scrolloff is not 15')
  return 'custom editor options applied'
end

local function check_hardening()
  assert(#vim.api.nvim_get_autocmds { event = 'PackChanged' } == 0, 'plugin build hooks are enabled')
  return 'automatic plugin build hooks disabled'
end

local function check_format_and_lint_policy()
  local formatters = require('conform').formatters_by_ft
  assert(vim.deep_equal(formatters.python, { 'ruff_organize_imports', 'ruff_format' }), 'Python is not formatted with Ruff')
  assert(vim.deep_equal(formatters.terraform, { 'terraform_fmt' }), 'Terraform formatter is not configured')
  assert(vim.deep_equal(formatters.yaml, { 'yamlfmt' }), 'YAML formatter is not configured')

  local linters = require('lint').linters_by_ft
  assert(vim.deep_equal(linters.dockerfile, { 'hadolint' }), 'Dockerfile linter is not Hadolint')
  assert(vim.deep_equal(linters.terraform, { 'tflint' }), 'Terraform linter is not TFLint')
  assert(vim.deep_equal(linters.yaml, { 'yamllint' }), 'YAML linter is not yamllint')
  local autocmds = vim.api.nvim_get_autocmds { group = 'nvim2-lint' }
  assert(#autocmds == 1 and autocmds[1].event == 'BufWritePost', 'linting should run only after saving')
  return 'Ruff formatting and configured linters are active'
end

local function check_lsp_and_tool_policy()
  local lsp = require 'custom.lsp'
  local servers = vim.tbl_keys(lsp.servers)
  assert(#servers > 0, 'no LSP servers are configured')
  assert(#lsp.tools > 0, 'no Mason tools are configured')
  for _, tool in ipairs(lsp.tools) do
    assert(type(tool.version) == 'string' and tool.version ~= '', ('Mason tool is not pinned: %s'):format(tool[1]))
  end
  return ('%d servers and %d pinned tools configured'):format(#servers, #lsp.tools)
end

local function check_mason_tools()
  local registry = require 'mason-registry'
  local tools = require('custom.lsp').tools
  for _, tool in ipairs(tools) do
    local package = registry.get_package(tool[1])
    assert(package:is_installed(), ('Mason package is missing: %s; run :Nvim2ToolsInstallSync'):format(tool[1]))
    local installed = package:get_installed_version()
    assert(installed == tool.version, ('Mason version mismatch for %s: expected %s, found %s'):format(tool[1], tool.version, installed or 'unknown'))
  end
  return ('%d Mason packages installed at pinned versions'):format(#tools)
end

local function check_treesitter_parsers()
  local configured = require('custom.treesitter').parsers
  local installed = require('nvim-treesitter').get_installed 'parsers'
  for _, parser in ipairs(configured) do
    assert(vim.tbl_contains(installed, parser), ('Treesitter parser is missing: %s; run :Nvim2ToolsInstallSync'):format(parser))
  end
  return ('%d configured Treesitter parsers installed'):format(#configured)
end

---@param opts? { tools?: boolean }
function M.run(opts)
  opts = opts or {}
  local results = {}
  add_check(results, 'Recorded errors', function()
    assert(vim.v.errmsg == '', vim.v.errmsg)
    return 'none recorded'
  end)
  add_check(results, 'Neovim version', function()
    assert(vim.fn.has 'nvim-0.12' == 1, ('requires Neovim 0.12; found %s'):format(vim.version()))
    return tostring(vim.version())
  end)
  add_check(results, 'Plugin lock', check_plugin_lock)
  add_check(results, 'Custom modules', check_custom_modules)
  add_check(results, 'Plugin APIs', check_plugin_apis)
  add_check(results, 'Mappings', check_mappings)
  add_check(results, 'Commands', check_commands)
  add_check(results, 'Options', check_options)
  add_check(results, 'Hardening', check_hardening)
  add_check(results, 'Formatting and linting', check_format_and_lint_policy)
  add_check(results, 'LSP and tool policy', check_lsp_and_tool_policy)
  if opts.tools ~= false then
    add_check(results, 'Mason tools', check_mason_tools)
    add_check(results, 'Treesitter parsers', check_treesitter_parsers)
  end
  return results
end

function M.assert_all(opts)
  local failures = {}
  local results = M.run(opts)
  for _, result in ipairs(results) do
    if not result.ok then table.insert(failures, ('- %s: %s'):format(result.name, result.detail)) end
  end
  if #failures > 0 then error('Nvim2 checks failed:\n' .. table.concat(failures, '\n'), 0) end
  return results
end

return M
