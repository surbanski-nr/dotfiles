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
  local expected = {}
  local mason_bin = vim.fs.joinpath(vim.fn.stdpath 'data', 'mason', 'bin')
  for _, tool in ipairs(tools) do
    expected[tool[1]] = true
    local package = registry.get_package(tool[1])
    assert(package:is_installed(), ('Mason package is missing: %s; run :Nvim2ToolsInstallSync'):format(tool[1]))
    local installed = package:get_installed_version()
    assert(installed == tool.version, ('Mason version mismatch for %s: expected %s, found %s'):format(tool[1], tool.version, installed or 'unknown'))
    for executable in pairs(package:get_receipt():get():get_links().bin) do
      local path = vim.fs.joinpath(mason_bin, executable)
      assert(vim.fn.executable(path) == 1, ('Mason executable is unavailable: %s (%s)'):format(executable, tool[1]))
    end
  end

  local extra = vim.iter(registry.get_installed_package_names()):filter(function(name) return not expected[name] end):totable()
  table.sort(extra)
  assert(#extra == 0, 'undeclared Mason packages are installed: ' .. table.concat(extra, ', '))
  return ('%d Mason packages and their launchers match the declarations'):format(#tools)
end

local function check_tool_probes()
  local mason_bin = vim.fs.joinpath(vim.fn.stdpath 'data', 'mason', 'bin')
  local probes = require('custom.lsp').tool_probes
  for _, probe in ipairs(probes) do
    local command = vim.list_extend({ vim.fs.joinpath(mason_bin, probe[1]) }, vim.list_slice(probe, 2))
    local result = vim.system(command, { text = true, timeout = 5000 }):wait()
    assert(result.code == 0, ('Mason executable failed: %s\n%s'):format(table.concat(probe, ' '), vim.trim(result.stderr or '')))
  end
  return ('%d Mason executables started successfully'):format(#probes)
end

local function check_treesitter_parsers()
  local configured = require('custom.treesitter').parsers
  local installed = require('nvim-treesitter').get_installed 'parsers'
  local expected = {}
  for _, parser in ipairs(configured) do
    expected[parser] = true
    assert(vim.tbl_contains(installed, parser), ('Treesitter parser is missing: %s; run :Nvim2ToolsInstallSync'):format(parser))
  end
  local extra = vim.iter(installed):filter(function(parser) return not expected[parser] end):totable()
  table.sort(extra)
  assert(#extra == 0, 'undeclared Treesitter parsers are installed: ' .. table.concat(extra, ', '))
  return ('%d Treesitter parsers match the declarations'):format(#configured)
end

function M.run(opts)
  opts = opts or {}
  local results = {}
  add_check(results, 'Neovim version', function()
    assert(vim.version.ge(vim.version(), { 0, 12, 4 }), ('requires Neovim 0.12.4 or newer; found %s'):format(vim.version()))
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
    add_check(results, 'Mason executable probes', check_tool_probes)
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
