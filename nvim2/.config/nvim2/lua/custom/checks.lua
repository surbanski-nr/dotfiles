local M = {}

local function add_check(results, name, callback)
  local ok, detail = pcall(callback)
  results[#results + 1] = {
    name = name,
    ok = ok,
    detail = ok and detail or tostring(detail),
  }
end

local function check_plugin_lock()
  local path = vim.fs.joinpath(vim.fn.stdpath 'config', 'nvim-pack-lock.json')
  local locked = vim.json.decode(table.concat(vim.fn.readfile(path), '\n')).plugins
  local active = {}

  for _, plugin in ipairs(vim.pack.get(nil, { info = false })) do
    active[plugin.spec.name] = plugin.rev
  end
  for name, plugin in pairs(locked) do
    assert(active[name] == plugin.rev, ('plugin revision mismatch: %s'):format(name))
    active[name] = nil
  end
  local extra = next(active)
  assert(extra == nil, ('active plugin is missing from nvim-pack-lock.json: %s'):format(extra))

  return ('%d plugins match nvim-pack-lock.json'):format(vim.tbl_count(locked))
end

local function check_tool_declarations()
  local tools = require('custom.lsp').tools
  for _, tool in ipairs(tools) do
    assert(type(tool.version) == 'string' and tool.version ~= '', ('Mason tool is not pinned: %s'):format(tool[1]))
  end
  return ('%d Mason tools have pinned versions'):format(#tools)
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
  return ('%d Mason packages match their pinned versions'):format(#tools)
end

local function check_treesitter_parsers()
  local configured = require('custom.treesitter').parsers
  local installed = require('nvim-treesitter').get_installed 'parsers'
  for _, parser in ipairs(configured) do
    assert(vim.tbl_contains(installed, parser), ('Treesitter parser is missing: %s; run :Nvim2ToolsInstallSync'):format(parser))
  end
  return ('%d configured Treesitter parsers installed'):format(#configured)
end

function M.run(opts)
  opts = opts or {}
  local results = {}
  add_check(results, 'Neovim version', function()
    assert(vim.fn.has 'nvim-0.12' == 1, ('requires Neovim 0.12; found %s'):format(vim.version()))
    return tostring(vim.version())
  end)
  add_check(results, 'Plugin lock', check_plugin_lock)
  add_check(results, 'Plugin build hooks', function()
    assert(#vim.api.nvim_get_autocmds { event = 'PackChanged' } == 0, 'plugin build hooks are enabled')
    return 'disabled'
  end)
  add_check(results, 'Tool declarations', check_tool_declarations)
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
    if not result.ok then failures[#failures + 1] = ('- %s: %s'):format(result.name, result.detail) end
  end
  if #failures > 0 then error('Nvim2 checks failed:\n' .. table.concat(failures, '\n'), 0) end
  return results
end

return M
