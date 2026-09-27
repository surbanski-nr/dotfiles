local M = {}

local command_timeout = 5000

local function add_check(results, name, callback)
  local ok, detail = pcall(callback)
  results[#results + 1] = {
    name = name,
    ok = ok,
    detail = ok and detail or tostring(detail),
  }
end

local function read_plugin_lock()
  local path = vim.fs.joinpath(vim.fn.stdpath 'config', 'nvim-pack-lock.json')
  assert(vim.uv.fs_stat(path), ('plugin lock is missing: %s'):format(path))

  local read_ok, lines = pcall(vim.fn.readfile, path)
  assert(read_ok, ('could not read plugin lock %s: %s'):format(path, lines))

  local decode_ok, decoded = pcall(vim.json.decode, table.concat(lines, '\n'))
  assert(decode_ok, ('plugin lock contains invalid JSON: %s'):format(decoded))
  assert(type(decoded) == 'table' and not vim.islist(decoded), 'plugin lock root must be a JSON object')
  assert(type(decoded.plugins) == 'table' and not vim.islist(decoded.plugins), 'plugin lock must contain a plugins object')

  for name, plugin in pairs(decoded.plugins) do
    assert(type(name) == 'string' and name ~= '', 'plugin lock contains an invalid plugin name')
    assert(type(plugin) == 'table' and not vim.islist(plugin), ('plugin lock record is invalid: %s'):format(name))
    assert(type(plugin.src) == 'string' and plugin.src ~= '', ('plugin lock source is invalid: %s'):format(name))
    assert(type(plugin.rev) == 'string' and #plugin.rev == 40 and plugin.rev:match '^%x+$', ('plugin lock revision is invalid: %s'):format(name))
    if plugin.version ~= nil then assert(type(plugin.version) == 'string', ('plugin lock version is invalid: %s'):format(name)) end
  end

  return decoded.plugins
end

local function command_detail(result)
  local detail = vim.trim(result.stderr or '')
  if detail == '' then detail = vim.trim(result.stdout or '') end
  return detail ~= '' and detail or 'no output'
end

local function run_command(command, label)
  local spawn_ok, process = pcall(vim.system, command, { text = true, timeout = command_timeout })
  assert(spawn_ok, ('could not start %s: %s'):format(label, process))
  local wait_ok, result = pcall(process.wait, process)
  assert(wait_ok, ('could not wait for %s: %s'):format(label, result))
  if result.code == 124 then error(('%s timed out after %d ms'):format(label, command_timeout), 0) end
  assert(
    result.code == 0,
    ('%s exited with status %s%s: %s'):format(
      label,
      tostring(result.code),
      result.signal and (' (signal %s)'):format(result.signal) or '',
      command_detail(result)
    )
  )
  return vim.trim(result.stdout or '')
end

local function check_checkout(name, plugin, locked)
  assert(type(plugin.path) == 'string' and plugin.path ~= '', ('active plugin has no checkout path: %s'):format(name))
  local checkout = vim.uv.fs_realpath(plugin.path)
  assert(checkout, ('plugin checkout is missing: %s (%s)'):format(name, plugin.path))
  assert(vim.uv.fs_stat(vim.fs.joinpath(checkout, '.git')), ('plugin Git metadata is missing: %s (%s)'):format(name, checkout))

  local top = run_command({ 'git', '-C', checkout, 'rev-parse', '--show-toplevel' }, ('Git root probe for %s'):format(name))
  top = vim.uv.fs_realpath(top)
  assert(top == checkout, ('Git resolved %s outside its plugin checkout: %s'):format(name, top or 'unknown'))

  local head = run_command({ 'git', '-C', checkout, 'rev-parse', '--verify', 'HEAD^{commit}' }, ('Git HEAD probe for %s'):format(name))
  assert(head == locked.rev, ('plugin checkout revision mismatch for %s: expected %s, found %s'):format(name, locked.rev, head))

  local status =
    run_command({ 'git', '-C', checkout, 'status', '--short', '--untracked-files=no', '--ignore-submodules=none' }, ('Git status probe for %s'):format(name))
  assert(status == '', ('plugin checkout has tracked modifications: %s\n%s'):format(name, status))
end

local function check_plugin_lock()
  local locked = read_plugin_lock()
  local declared = {}

  for _, plugin in ipairs(vim.pack.get(nil, { info = false })) do
    local spec = plugin.spec or {}
    local name = spec.name
    assert(type(name) == 'string' and name ~= '', 'vim.pack returned a plugin without a name')
    assert(declared[name] == nil, ('vim.pack returned a duplicate plugin: %s'):format(name))
    declared[name] = plugin
  end

  for name, record in pairs(locked) do
    local plugin = declared[name]
    assert(plugin, ('locked plugin is not declared in this profile: %s'):format(name))
    assert(plugin.active == true, ('locked plugin is inactive in this profile: %s'):format(name))
    assert(plugin.spec.src == record.src, ('plugin source mismatch for %s: expected %s, found %s'):format(name, record.src, plugin.spec.src or 'missing'))
    check_checkout(name, plugin, record)
    declared[name] = nil
  end

  local extra_name
  for name, plugin in pairs(declared) do
    if plugin.active == true then
      extra_name = name
      break
    end
  end
  if extra_name then error(('active plugin is missing from nvim-pack-lock.json: %s'):format(extra_name), 0) end

  return ('%d active plugin checkouts match nvim-pack-lock.json and are clean'):format(vim.tbl_count(locked))
end

local function exact_version(version)
  if type(version) ~= 'string' or version == '' then return false end
  local normalized = version:gsub('^v', '')
  if normalized:match '^%d+%.%d+%.%d+$' then return true end
  return normalized:match '^%d+%.%d+%.%d+[-+][%w%.%-]+$' ~= nil
end

local function check_tool_declarations()
  local tools = require('custom.lsp').tools
  local names = {}
  for _, tool in ipairs(tools) do
    local name = tool[1]
    assert(type(name) == 'string' and name ~= '', 'Mason tool has an invalid name')
    assert(not names[name], ('duplicate Mason tool declaration: %s'):format(name))
    names[name] = true
    assert(exact_version(tool.version), ('Mason tool version is not exact for %s: %s'):format(name, tostring(tool.version)))
  end
  return ('%d Mason tools have unique exact versions'):format(#tools)
end

local function check_mason_tools()
  local registry = require 'mason-registry'
  local tools = require('custom.lsp').tools
  local expected = {}
  local mason_bin = vim.fs.joinpath(vim.fn.stdpath 'data', 'mason', 'bin')
  for _, tool in ipairs(tools) do
    local name = tool[1]
    expected[name] = true

    local package_ok, package = pcall(registry.get_package, name)
    assert(package_ok, ('Mason registry has no package %s: %s'):format(name, package))
    assert(package:is_installed(), ('Mason package is missing: %s; run :Nvim2ToolsInstallSync'):format(name))

    local version_ok, installed = pcall(package.get_installed_version, package)
    assert(version_ok, ('could not read Mason receipt version for %s: %s'):format(name, installed))
    assert(installed == tool.version, ('Mason version mismatch for %s: expected %s, found %s'):format(name, tool.version, installed or 'unknown'))

    local receipt_ok, receipt = pcall(function() return package:get_receipt():get() end)
    assert(receipt_ok, ('could not read Mason receipt for %s: %s'):format(name, receipt))
    local links_ok, links = pcall(receipt.get_links, receipt)
    assert(links_ok and type(links) == 'table' and type(links.bin) == 'table', ('Mason receipt has invalid launcher links for %s: %s'):format(name, links))
    for executable in pairs(links.bin) do
      local path = vim.fs.joinpath(mason_bin, executable)
      assert(vim.fn.executable(path) == 1, ('Mason launcher is missing or not executable: %s (%s)'):format(path, name))
    end
  end

  local installed_ok, installed_names = pcall(registry.get_installed_package_names)
  assert(installed_ok, ('could not list installed Mason packages: %s'):format(installed_names))
  local extra = vim.iter(installed_names):filter(function(name) return not expected[name] end):totable()
  table.sort(extra)
  assert(#extra == 0, 'undeclared Mason packages are installed: ' .. table.concat(extra, ', '))
  return ('%d Mason packages, receipts and launchers match the declarations'):format(#tools)
end

local function check_tool_probes()
  local mason_bin = vim.fs.joinpath(vim.fn.stdpath 'data', 'mason', 'bin')
  local probes = require('custom.lsp').tool_probes
  for _, probe in ipairs(probes) do
    local executable = vim.fs.joinpath(mason_bin, probe[1])
    local command = vim.list_extend({ executable }, vim.list_slice(probe, 2))
    run_command(command, ('Mason executable probe %s'):format(table.concat(probe, ' ')))
  end
  return ('%d Mason executables started successfully'):format(#probes)
end

local function check_treesitter_parsers()
  local configured = require('custom.treesitter').parsers
  local installed = require('nvim-treesitter').get_installed 'parsers'
  local expected = {}
  for _, parser in ipairs(configured) do
    assert(type(parser) == 'string' and parser ~= '', 'Treesitter parser declaration has an invalid name')
    assert(not expected[parser], ('duplicate Treesitter parser declaration: %s'):format(parser))
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
    assert(vim.version.ge(vim.version(), { 0, 12, 5 }), ('requires Neovim 0.12.5 or newer; found %s'):format(vim.version()))
    return tostring(vim.version())
  end)
  add_check(results, 'Plugin lock', check_plugin_lock)
  add_check(results, 'PackChanged policy', function()
    assert(#vim.api.nvim_get_autocmds { event = 'PackChanged' } == 0, 'PackChanged autocmds are prohibited by this profile')
    return 'no PackChanged autocmds'
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
