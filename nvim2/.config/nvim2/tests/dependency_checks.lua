local function command(args, opts)
  opts = opts or {}
  opts.text = true
  local result = vim.system(args, opts):wait(10000)
  assert(result.code == 0, ('command failed (%s): %s'):format(table.concat(args, ' '), result.stderr or result.stdout or ''))
  return vim.trim(result.stdout or '')
end

local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  assert(vim.fn.writefile(type(lines) == 'table' and lines or { lines }, path) == 0)
end

local function git(root, ...)
  local args = { 'git', '-C', root }
  vim.list_extend(args, { ... })
  return command(args)
end

local function make_repository(root, name)
  local path = vim.fs.joinpath(root, name)
  vim.fn.mkdir(path, 'p')
  command { 'git', 'init', '-q', path }
  git(path, 'config', 'user.name', 'Nvim2 test')
  git(path, 'config', 'user.email', 'nvim2-test@example.invalid')
  write(vim.fs.joinpath(path, 'plugin', name .. '.lua'), 'vim.g.' .. name .. ' = true')
  git(path, 'add', '.')
  git(path, 'commit', '-qm', 'first')
  local first = git(path, 'rev-parse', 'HEAD')
  write(vim.fs.joinpath(path, 'plugin', name .. '.lua'), 'vim.g.' .. name .. ' = 2')
  git(path, 'add', '.')
  git(path, 'commit', '-qm', 'second')
  return path, first, git(path, 'rev-parse', 'HEAD')
end

local function result_named(results, name)
  return vim.iter(results):find(function(result) return result.name == name end)
end

local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, 'p')

local function run_fixture(scenario)
  local root = vim.fs.joinpath(temporary, scenario)
  local source, first, second = make_repository(root, 'fixture')
  local extra_source = make_repository(root, 'extra')
  local config = vim.fs.joinpath(root, 'config', 'nvim2')
  local data = vim.fs.joinpath(root, 'data')
  local state = vim.fs.joinpath(root, 'state')
  local cache = vim.fs.joinpath(root, 'cache')
  local result_path = vim.fs.joinpath(root, 'result.json')
  local source_uri = 'file://' .. source
  local lock = { plugins = { fixture = { src = source_uri, rev = first } } }
  if scenario == 'corrupt-lock' then
    write(vim.fs.joinpath(config, 'nvim-pack-lock.json'), '{broken')
  else
    write(vim.fs.joinpath(config, 'nvim-pack-lock.json'), vim.json.encode(lock))
  end
  local locked_json = vim.json.encode(lock)

  local init = ([=[
vim.opt.runtimepath:prepend(%q)
local scenario = %q
if scenario ~= 'inactive' and scenario ~= 'corrupt-lock' then
  local specs = { { src = %q, name = 'fixture' } }
  if scenario == 'extra-active' then specs[#specs + 1] = { src = %q, name = 'extra' } end
  vim.pack.add(specs)
end
if scenario == 'extra-active' then
  assert(vim.fn.writefile({ %q }, vim.fs.joinpath(vim.fn.stdpath('config'), 'nvim-pack-lock.json')) == 0)
elseif scenario == 'source-mismatch' then
  local lock_path = vim.fs.joinpath(vim.fn.stdpath('config'), 'nvim-pack-lock.json')
  local lock = vim.json.decode(table.concat(vim.fn.readfile(lock_path), '\n'))
  lock.plugins.fixture.src = 'file:///source-does-not-match'
  assert(vim.fn.writefile({ vim.json.encode(lock) }, lock_path) == 0)
end

if scenario ~= 'corrupt-lock' then
  local plugin = vim.iter(vim.pack.get(nil, { info = false })):find(function(item)
    return item.spec and item.spec.name == 'fixture'
  end)
  if scenario == 'wrong-head' then
    assert(vim.system({ 'git', '-C', plugin.path, 'checkout', '--detach', %q }, { text = true }):wait(10000).code == 0)
  elseif scenario == 'missing-checkout' then
    assert(vim.uv.fs_rename(plugin.path, plugin.path .. '.missing'))
  elseif scenario == 'dirty-checkout' then
    assert(vim.fn.writefile({ 'vim.g.fixture = 3' }, vim.fs.joinpath(plugin.path, 'plugin', 'fixture.lua')) == 0)
  end
end

local checks = require 'custom.checks'
local results = checks.run { tools = false }
local assert_ok, assert_error = pcall(checks.assert_all, { tools = false })
local health_text
if scenario == 'wrong-head' then
  require 'custom.core'
  vim.cmd.Nvim2Check()
  health_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
end
assert(vim.fn.writefile({ vim.json.encode {
  results = results,
  assert_ok = assert_ok,
  assert_error = assert_error,
  health_text = health_text,
} }, %q) == 0)
]=]):format(vim.fn.stdpath 'config', scenario, source_uri, 'file://' .. extra_source, locked_json, second, result_path)
  write(vim.fs.joinpath(config, 'init.lua'), vim.split(init, '\n', { plain = true }))

  local environment = vim.tbl_extend('force', vim.fn.environ(), {
    XDG_CONFIG_HOME = vim.fs.dirname(config),
    XDG_DATA_HOME = data,
    XDG_STATE_HOME = state,
    XDG_CACHE_HOME = cache,
    NVIM_APPNAME = 'nvim2',
  })
  local process = vim.system({ vim.v.progpath, '--headless', '+qa!' }, { env = environment, text = true }):wait(30000)
  assert(process.code == 0, ('fixture %s failed to run: %s'):format(scenario, process.stderr or process.stdout or ''))
  assert(vim.uv.fs_stat(result_path), ('fixture %s produced no result; stdout: %s; stderr: %s'):format(scenario, process.stdout or '', process.stderr or ''))
  local decoded = vim.json.decode(table.concat(vim.fn.readfile(result_path), '\n'))
  return decoded, first, second
end

local matching = run_fixture 'matching'
assert(result_named(matching.results, 'Plugin lock').ok, vim.inspect(matching.results))
assert(matching.assert_ok, matching.assert_error)

local expected_failures = {
  ['wrong-head'] = 'revision mismatch',
  inactive = 'inactive',
  ['missing-checkout'] = 'checkout is missing',
  ['corrupt-lock'] = 'invalid JSON',
  ['extra-active'] = 'missing from nvim-pack-lock.json',
  ['source-mismatch'] = 'source mismatch',
  ['dirty-checkout'] = 'tracked modifications',
}
for scenario, expected in pairs(expected_failures) do
  local result = run_fixture(scenario)
  local plugin_check = result_named(result.results, 'Plugin lock')
  assert(plugin_check and not plugin_check.ok, scenario .. ' unexpectedly passed')
  assert(plugin_check.detail:find(expected, 1, true), ('%s reported %q, expected %q'):format(scenario, plugin_check.detail, expected))
  assert(not result.assert_ok and result.assert_error:find(expected, 1, true), scenario .. ' did not fail assert_all')
  if scenario == 'wrong-head' then assert(result.health_text and result.health_text:find(expected, 1, true), ':Nvim2Check hid the checkout mismatch') end
end

local checks = require 'custom.checks'
local lsp = require 'custom.lsp'
local original_tools = lsp.tools
lsp.tools = { { 'rolling', version = 'latest' } }
local rolling_results = checks.run { tools = false }
lsp.tools = {
  { 'duplicate', version = '1.2.3' },
  { 'duplicate', version = '1.2.3' },
}
local duplicate_results = checks.run { tools = false }
lsp.tools = original_tools
local rolling_declarations = result_named(rolling_results, 'Tool declarations')
assert(rolling_declarations and not rolling_declarations.ok and rolling_declarations.detail:find('not exact', 1, true), 'rolling tool version was accepted')
local duplicate_declarations = result_named(duplicate_results, 'Tool declarations')
assert(
  duplicate_declarations and not duplicate_declarations.ok and duplicate_declarations.detail:find('duplicate', 1, true),
  'duplicate tool declaration was accepted'
)
assert(result_named(rolling_results, 'PackChanged policy'), 'a failed category stopped subsequent reporting')

if vim.env.NVIM2_CHECK_TOOLS ~= '0' then
  local original_probes = lsp.tool_probes
  lsp.tool_probes = { { 'nvim2-executable-that-does-not-exist', '--version' } }
  local probe_results = checks.run()
  lsp.tool_probes = original_probes
  local probe = result_named(probe_results, 'Mason executable probes')
  assert(probe and not probe.ok and probe.detail:find('could not start', 1, true), 'missing executable probe was not actionable')
  assert(result_named(probe_results, 'Treesitter parsers'), 'failed executable stopped later categories')
end

vim.fn.delete(temporary, 'rf')
io.stdout:write 'Nvim2 dependency checks passed\n'
vim.cmd 'qa!'
