local dap = require 'dap'
local temporary = vim.fn.tempname()
local adapter_pids = {}
local debuggee_pids = {}
local child
local exit_code

local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  assert(vim.fn.writefile(lines, path) == 0, 'could not write Go debugger fixture: ' .. path)
end

local function wait_for(predicate, message) assert(vim.wait(15000, predicate, 10), message) end

local function response(request)
  local done, result, failure = false, nil, nil
  request(function(err, body)
    failure, result, done = err, body, true
  end)
  wait_for(function() return done end, 'Delve request timed out')
  assert(not failure, vim.inspect(failure))
  return result
end

local function evaluate(expression)
  return response(function(callback) dap.session():evaluate(expression, callback) end).result
end

local function panels_open()
  return vim.iter(vim.api.nvim_list_wins()):any(function(win) return vim.bo[vim.api.nvim_win_get_buf(win)].filetype:match '^dapui_' ~= nil end)
end

local function breakpoint(path, line)
  dap.clear_breakpoints()
  vim.api.nvim_cmd({ cmd = 'edit', args = { path } }, {})
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  dap.set_breakpoint()
end

local function stopped(line)
  wait_for(function()
    local session = dap.session()
    return session and session.stopped_thread_id and session.current_frame and session.current_frame.line == line
  end, 'Go did not stop at line ' .. line)
  local pid = vim.fn.getpid()
  for child_pid in table.concat(vim.fn.readfile(('/proc/%d/task/%d/children'):format(pid, pid)), ' '):gmatch '%d+' do
    local command = io.open('/proc/' .. child_pid .. '/cmdline', 'rb')
    if command then
      local arguments = command:read '*a'
      command:close()
      if arguments:find('dlv', 1, true) then adapter_pids[tonumber(child_pid)] = true end
    end
  end
end

local function closed()
  wait_for(function() return next(dap.sessions()) == nil and not panels_open() end, 'Go debugger session or panels did not close')
  for pid in pairs(adapter_pids) do
    wait_for(function() return not vim.uv.kill(pid, 0) end, 'Go debugger left Delve running')
  end
  for pid in pairs(debuggee_pids) do
    wait_for(function() return not vim.uv.kill(pid, 0) end, 'Go debugger left the debuggee running')
  end
  adapter_pids = {}
  debuggee_pids = {}
end

local function launch(name)
  local config = vim.iter(dap.configurations.go):find(function(candidate) return candidate.name == 'Go: ' .. name end)
  dap.run(vim.deepcopy(assert(config, 'missing Go configuration: ' .. name)))
end

local function finish()
  exit_code = nil
  dap.continue()
  closed()
  assert(exit_code == 0, 'Go debuggee did not finish successfully')
end

local function run()
  if vim.env.NVIM2_CHECK_TOOLS == '0' then return end
  vim.env.GOPROXY = 'off'
  vim.env.GOTOOLCHAIN = 'local'
  local root = vim.fs.joinpath(temporary, 'Go project with spaces')
  local package = vim.fs.joinpath(root, 'cmd', 'app')
  local main = vim.fs.joinpath(package, 'main.go')
  write(vim.fs.joinpath(root, 'go.mod'), { 'module example.com/nvim2-debug', '', 'go 1.25.0' })
  write(vim.fs.joinpath(package, 'answer.go'), { 'package main', '', 'func answer() int { return 42 }' })
  write(main, {
    'package main',
    '',
    'import "os"',
    '',
    'func main() {',
    '\tvalue := answer()',
    '\tresult := value + 1',
    '\tos.WriteFile("result.txt", []byte{byte(result)}, 0600)',
    '}',
  })
  local test = vim.fs.joinpath(package, 'main_test.go')
  write(vim.fs.joinpath(package, 'testdata', 'answer.txt'), { '42' })
  write(test, {
    'package main',
    '',
    'import ("os"; "testing")',
    '',
    'func TestAnswer(t *testing.T) {',
    '\tvalue := answer()',
    '\tif value != 42 {',
    '\t\tt.Fatal(value)',
    '\t}',
    '}',
    '',
    'func TestNotSelected(t *testing.T) {',
    '\tt.Fatal("another test ran")',
    '}',
    '',
    'func TestFixture(t *testing.T) {',
    '\tdata, err := os.ReadFile("testdata/answer.txt")',
    '\tif err != nil { t.Fatal(err) }',
    '\tif string(data) != "42\\n" { t.Fatal(string(data)) }',
    '\tif err := os.WriteFile("fixture-read.txt", data, 0600); err != nil { t.Fatal(err) }',
    '}',
  })
  local ordinary_test = vim
    .system(require('custom.go').command('go', 'test', '-run', '^TestFixture$', './cmd/app'), {
      cwd = root,
      text = true,
      env = { GOPROXY = 'off', GOTOOLCHAIN = 'local' },
    })
    :wait(30000)
  assert(ordinary_test.code == 0, 'ordinary go test failed to read testdata: ' .. (ordinary_test.stderr or ''))
  local outside = vim.fs.joinpath(temporary, 'outside')
  vim.fn.mkdir(outside, 'p')
  vim.fn.chdir(outside)
  dap.listeners.after.event_exited['nvim2.go-checks'] = function(_, event) exit_code = event.exitCode end
  dap.listeners.after.event_process['nvim2.go-checks'] = function(_, event) debuggee_pids[event.systemProcessId] = true end

  breakpoint(main, 7)
  launch 'launch package'
  stopped(7)
  assert(next(adapter_pids), 'Go launch did not start an observable Delve process')
  assert(next(debuggee_pids), 'Delve did not report the launched process')
  assert(evaluate 'value' == '42', 'Go locals did not expose the value from another package file')
  wait_for(panels_open, 'Go debugger panels did not open')
  local threads = response(function(callback) dap.session():request('threads', {}, callback) end).threads
  assert(#threads > 0, 'Delve returned no goroutines')
  local scopes = response(function(callback) dap.session():request('scopes', { frameId = dap.session().current_frame.id }, callback) end).scopes
  local variables =
    response(function(callback) dap.session():request('variables', { variablesReference = scopes[1].variablesReference }, callback) end).variables
  assert(
    vim.iter(variables):any(function(variable) return variable.name == 'value' and variable.value == '42' end),
    'Delve returned no expected local variable'
  )
  dap.step_over()
  stopped(8)
  assert(evaluate 'result' == '43', 'Go step over did not execute the stopped statement')
  finish()
  assert(vim.fn.readfile(vim.fs.joinpath(root, 'result.txt'), 'b')[1] == '+', 'Go launch did not use the module working directory')
  assert(vim.fn.getcwd() == outside, 'Go debugger changed Neovim cwd')

  breakpoint(test, 7)
  assert(vim.wait(3000, function() return vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()] ~= nil end), 'Go test parser did not attach')
  vim.fn.maparg('<leader>dt', 'n', false, true).callback()
  stopped(7)
  assert(dap.session().config.mode == 'test', 'Go test key launched a normal program')
  assert(evaluate 'value' == '42', 'nearest Go test did not expose its local value')
  finish()

  local fixture_read = vim.fs.joinpath(package, 'fixture-read.txt')
  vim.fn.delete(fixture_read)
  breakpoint(test, 13)
  vim.fn.maparg('<leader>dT', 'n', false, true).callback()
  stopped(13)
  assert(dap.session().config.mode == 'test' and not dap.session().config.args, 'package test shortcut kept the nearest-test filter')
  exit_code = nil
  dap.continue()
  closed()
  assert(exit_code == 1, 'package test did not run the deliberately failing second test')
  assert(vim.fn.readfile(fixture_read)[1] == '42', 'package test shortcut did not read package-relative testdata')

  vim.fn.delete(fixture_read)
  breakpoint(test, 18)
  vim.fn.maparg('<leader>dt', 'n', false, true).callback()
  stopped(18)
  finish()
  assert(vim.fn.readfile(fixture_read)[1] == '42', 'nearest test did not read package-relative testdata')
  vim.fn.delete(fixture_read)
  breakpoint(test, 18)
  launch 'test package'
  stopped(18)
  exit_code = nil
  dap.continue()
  closed()
  assert(exit_code == 1, 'package test did not retain the deliberately failing test')
  assert(vim.fn.readfile(fixture_read)[1] == '42', 'package launch did not read package-relative testdata')

  breakpoint(main, 7)
  launch 'launch package'
  stopped(7)
  vim.fn.maparg('<leader>dq', 'n', false, true).callback()
  closed()

  local pid_file = vim.fs.joinpath(root, 'exit-pids')
  local result
  child = vim.system({ vim.v.progpath, '--headless', "+lua dofile(vim.fn.stdpath('config') .. '/tests/fixtures/go_debug_exit.lua')" }, {
    text = true,
    timeout = 20000,
    env = { NVIM2_GO_DEBUG_FILE = main, NVIM2_GO_DEBUG_PID_FILE = pid_file },
  }, function(value) result = value end)
  wait_for(function() return result ~= nil end, 'Neovim exit did not finish with live Go debugging')
  assert(result.code == 0, 'Go exit fixture failed: ' .. vim.inspect(result))
  for _, pid in ipairs(vim.fn.readfile(pid_file)) do
    wait_for(function() return not vim.uv.kill(tonumber(pid), 0) end, 'Neovim exit left a Go/Delve process running')
  end
  io.stdout:write 'Nvim2 Go debugger checks passed (multi-file package, module cwd, breakpoint, variables, goroutines, step, isolated nearest test, whole-package test, package testdata, terminate/cleanup, Neovim exit)\n'
end

local ok, message = xpcall(run, debug.traceback)
if child then child:kill(9) end
if next(dap.sessions()) ~= nil then
  dap.terminate { all = true, hierarchy = true }
  vim.wait(3000, function() return next(dap.sessions()) == nil end)
end
for pid in pairs(adapter_pids) do
  if vim.uv.kill(pid, 0) then vim.uv.kill(pid, 9) end
end
for pid in pairs(debuggee_pids) do
  if vim.uv.kill(pid, 0) then vim.uv.kill(pid, 9) end
end
for _, client in ipairs(vim.lsp.get_clients()) do
  client:stop(true)
end
vim.fn.delete(temporary, 'rf')
if not ok then
  io.stderr:write(message .. '\n')
  vim.cmd 'cquit 1'
else
  vim.cmd 'qa!'
end
