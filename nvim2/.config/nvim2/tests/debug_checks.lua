local dap = require 'dap'
local python = require 'dap-python'
local saved_test_runner = python.test_runner
local temporary
local children = {}
local lsp_clients = {}
local adapter_pids = {}
local terminal_jobs = {}
local environment = { 'VIRTUAL_ENV', 'CONDA_PREFIX', 'NVIM2_DEBUG_PYTHON', 'NVIM2_DEBUG_CHECK_ENV', 'NVIM2_DEBUG_CHECK_OUTSIDE' }
local saved_environment = {}
for _, name in ipairs(environment) do
  saved_environment[name] = vim.env[name]
end
local original_cwd = vim.fn.getcwd()

local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  assert(vim.fn.writefile(lines, path) == 0, 'could not write debugger fixture: ' .. path)
end

local function wait_for(predicate, message, milliseconds) assert(vim.wait(milliseconds or 10000, predicate, 10), message) end

local function response(request)
  local done, result, failure = false, nil, nil
  request(function(err, body)
    failure, result, done = err, body, true
  end)
  wait_for(function() return done end, 'debug adapter request timed out')
  assert(not failure, vim.inspect(failure))
  return result
end

local function evaluate(expression)
  return response(function(callback) dap.session():evaluate(expression, callback) end).result
end

local function project_environment()
  assert(evaluate '__import__("os").getenv("NVIM2_DEBUG_CHECK_ENV") == "project"' == 'True', 'debuggee did not load the project .env')
  assert(evaluate '__import__("os").getenv("NVIM2_DEBUG_CHECK_OUTSIDE") is None' == 'True', 'debuggee loaded .env from Neovim cwd')
end

local function panels()
  return vim
    .iter(vim.api.nvim_list_wins())
    :filter(function(window) return vim.bo[vim.api.nvim_win_get_buf(window)].filetype:match '^dapui_' ~= nil end)
    :totable()
end

local function stopped(line)
  wait_for(function()
    local session = dap.session()
    return session and session.stopped_thread_id and session.current_frame and session.current_frame.line == line
  end, 'Python did not stop at line ' .. line)
  local terminal = dap.session().term_buf
  if terminal then terminal_jobs[vim.bo[terminal].channel] = true end
  local pid = vim.fn.getpid()
  for child_pid in table.concat(vim.fn.readfile(('/proc/%d/task/%d/children'):format(pid, pid)), ' '):gmatch '%d+' do
    local command = io.open('/proc/' .. child_pid .. '/cmdline', 'rb')
    if command then
      local arguments = command:read '*a'
      command:close()
      if arguments:find('debugpy.adapter', 1, true) then adapter_pids[tonumber(child_pid)] = true end
    end
  end
end

local function closed()
  wait_for(function() return next(dap.sessions()) == nil and #panels() == 0 end, 'debugger session or panels did not close')
  for pid in pairs(adapter_pids) do
    wait_for(function() return not vim.uv.kill(pid, 0) end, 'debugger left an adapter process running')
  end
  for job in pairs(terminal_jobs) do
    wait_for(function() return vim.fn.jobwait({ job }, 0)[1] ~= -1 end, 'debugger left an integrated terminal job running')
  end
end

local function breakpoint(path, line)
  dap.clear_breakpoints()
  vim.api.nvim_cmd({ cmd = 'edit', args = { path } }, {})
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  dap.set_breakpoint()
end

local function run()
  if vim.env.NVIM2_CHECK_TOOLS == '0' then
    io.stdout:write 'Nvim2 debugger checks skipped because tools are disabled\n'
    return
  end

  for _, name in ipairs(environment) do
    vim.env[name] = nil
  end
  python.test_runner = nil
  temporary = vim.fn.tempname()
  local project = vim.fs.joinpath(temporary, 'project with spaces')
  local outside = vim.fs.joinpath(temporary, 'outside')
  vim.fn.mkdir(outside, 'p')
  write(vim.fs.joinpath(project, 'pyproject.toml'), { '[project]', 'name = "nvim2-debug-check"', 'version = "0.0.0"' })
  write(vim.fs.joinpath(project, '.env'), { 'NVIM2_DEBUG_CHECK_ENV=project' })
  write(vim.fs.joinpath(outside, '.env'), { 'NVIM2_DEBUG_CHECK_ENV=outside', 'NVIM2_DEBUG_CHECK_OUTSIDE=unexpected' })
  local adapter_python = vim.fs.joinpath(vim.fn.stdpath 'data', 'mason', 'packages', 'debugpy', 'venv', 'bin', 'python')
  local venv = vim.fs.joinpath(project, '.venv')
  local creation = vim.system({ adapter_python, '-I', '-B', '-m', 'venv', '--without-pip', venv }, { text = true }):wait(10000)
  assert(creation.code == 0, 'could not create project venv: ' .. (creation.stderr or ''))
  local project_python = vim.fs.joinpath(venv, 'bin', 'python')
  local site = vim.system({ project_python, '-I', '-B', '-c', 'import sysconfig; print(sysconfig.get_path("purelib"))' }, { text = true }):wait(5000)
  assert(site.code == 0, site.stderr)
  write(vim.trim(site.stdout) .. '/project_marker.py', { 'VALUE = 42' })

  local result_file = vim.fs.joinpath(project, 'result.txt')
  local sample = vim.fs.joinpath(project, 'sample.py')
  write(sample, {
    'import os',
    'import sys',
    'import project_marker',
    'value = project_marker.VALUE',
    'result = value + 1',
    'with open("result.txt", "w") as output:',
    '    output.write(str(result))',
  })
  vim.fn.chdir(outside)
  breakpoint(sample, 5)
  assert(require('custom.debug').python() == project_python, 'project venv was not selected from outside the project')

  vim.env.VIRTUAL_ENV = venv
  vim.b.nvim2_debug_python = adapter_python
  assert(require('custom.debug').python() == adapter_python, 'explicit interpreter did not override the active environment')
  vim.b.nvim2_debug_python = nil
  assert(require('custom.debug').python() == project_python, 'active virtual environment was not selected')
  vim.env.VIRTUAL_ENV = vim.fs.joinpath(temporary, 'missing environment')
  local valid, message = pcall(require('custom.debug').python)
  assert(not valid and tostring(message):find('VIRTUAL_ENV', 1, true), 'invalid active environment silently fell back to another Python')
  vim.env.VIRTUAL_ENV = nil

  local prompt = vim.fn.input
  local prompts_ok, prompt_error = pcall(function()
    vim.fn.input = function() return '' end
    assert(dap.configurations.python[3].module() == dap.ABORT, 'empty module prompt did not cancel launch')
    assert(dap.configurations.python[4].connect() == dap.ABORT, 'empty port prompt did not cancel attach')
    for _, invalid in ipairs { 'not a port', '0', '65536', '1.5' } do
      vim.fn.input = function() return invalid end
      assert(not pcall(dap.configurations.python[4].connect), 'attach accepted an invalid port: ' .. invalid)
    end
  end)
  vim.fn.input = prompt
  assert(prompts_ok, prompt_error)

  local exits = {}
  dap.listeners.after.event_exited['nvim2.checks'] = function(_, event) table.insert(exits, event.exitCode) end
  dap.run(vim.deepcopy(dap.configurations.python[1]))
  stopped(5)
  assert(next(adapter_pids), 'launch did not start an observable debugpy adapter process')
  assert(evaluate 'value' == '42', 'project-only dependency did not load in the selected venv')
  assert(evaluate('sys.prefix == ' .. vim.json.encode(venv)) == 'True', 'debuggee bypassed pyvenv.cfg')
  assert(evaluate('os.getcwd() == ' .. vim.json.encode(project)) == 'True', 'launch cwd was not the project root')
  project_environment()
  local pid = tonumber(evaluate 'os.getpid()')
  assert(pid and vim.uv.kill(pid, 0), 'debuggee process is not running')
  wait_for(function() return #panels() > 0 end, 'debugger panels did not open')
  local scopes = response(function(callback) dap.session():request('scopes', { frameId = dap.session().current_frame.id }, callback) end).scopes
  local variables =
    response(function(callback) dap.session():request('variables', { variablesReference = scopes[1].variablesReference }, callback) end).variables
  assert(
    vim.iter(variables):any(function(variable) return variable.name == 'value' and variable.value == '42' end),
    'locals did not expose the value at the breakpoint'
  )
  dap.step_over()
  stopped(6)
  assert(evaluate 'result' == '43', 'step over did not execute the stopped statement')
  dap.continue()
  closed()
  assert(exits[#exits] == 0 and vim.fn.readfile(result_file)[1] == '43', 'file launch did not finish successfully')
  wait_for(function() return not vim.uv.kill(pid, 0) end, 'file launch left a debuggee process running')

  breakpoint(sample, 5)
  local module = vim.deepcopy(dap.configurations.python[3])
  module.module = 'sample'
  dap.run(module)
  stopped(5)
  assert(evaluate 'project_marker.VALUE' == '42', 'module launch used the wrong interpreter or import root')
  project_environment()
  dap.continue()
  closed()
  assert(exits[#exits] == 0, 'module launch failed')

  local launch_directory = vim.fs.joinpath(project, 'launch directory')
  local custom_environment = vim.fs.joinpath(project, 'custom.env')
  write(vim.fs.joinpath(launch_directory, '.env'), { 'NVIM2_DEBUG_CHECK_ENV=launch-directory' })
  write(custom_environment, { 'NVIM2_DEBUG_CHECK_ENV=explicit-file' })
  for _, explicit in ipairs { false, true } do
    breakpoint(sample, 5)
    local launch = vim.deepcopy(dap.configurations.python[1])
    launch.cwd = launch_directory
    if explicit then launch.envFile = custom_environment end
    dap.run(launch)
    stopped(5)
    local expected = explicit and 'explicit-file' or 'launch-directory'
    assert(
      evaluate('__import__("os").getenv("NVIM2_DEBUG_CHECK_ENV") == ' .. vim.json.encode(expected)) == 'True',
      'launch cwd or explicit envFile was ignored'
    )
    dap.continue()
    closed()
    assert(exits[#exits] == 0, 'launch with custom environment failed')
  end

  assert(vim.fn.delete(vim.fs.joinpath(project, '.env')) == 0, 'could not remove the project .env fixture')
  breakpoint(sample, 5)
  dap.run(vim.deepcopy(dap.configurations.python[1]))
  stopped(5)
  assert(evaluate '__import__("os").getenv("NVIM2_DEBUG_CHECK_ENV") is None' == 'True', 'missing project .env fell back to Neovim cwd')
  assert(evaluate '__import__("os").getenv("NVIM2_DEBUG_CHECK_OUTSIDE") is None' == 'True', 'missing project .env loaded unrelated variables')
  dap.continue()
  closed()
  assert(exits[#exits] == 0, 'launch without a project .env failed')
  write(vim.fs.joinpath(project, '.env'), { 'NVIM2_DEBUG_CHECK_ENV=project' })

  local other_project = vim.fs.joinpath(temporary, 'unrelated pytest project')
  local other_file = vim.fs.joinpath(other_project, 'other.py')
  write(vim.fs.joinpath(other_project, 'pytest.ini'), { '[pytest]' })
  write(other_file, { 'value = 42' })
  vim.api.nvim_cmd({ cmd = 'edit', args = { other_file } }, {})
  local client_id = assert(
    vim.lsp.start {
      name = 'nvim2-debug-check-pyright',
      cmd = { vim.fn.exepath 'pyright-langserver', '--stdio' },
      root_dir = other_project,
    },
    'could not start the unrelated project LSP'
  )
  table.insert(lsp_clients, client_id)
  wait_for(function()
    local client = vim.lsp.get_client_by_id(client_id)
    return client and client.initialized
  end, 'unrelated project LSP did not initialize')

  local test_file = vim.fs.joinpath(project, 'test_sample.py')
  write(test_file, {
    'import unittest',
    'import project_marker',
    'class SampleTest(unittest.TestCase):',
    '    def test_value(self):',
    '        value = project_marker.VALUE',
    '        self.assertEqual(value, 42)',
    '    def test_not_selected(self):',
    '        self.fail("the cursor-selected test must not run the whole module")',
  })
  breakpoint(test_file, 6)
  require('custom.debug').test 'method'
  assert(vim.fn.getcwd() == outside, 'cursor test changed the working directory')
  stopped(6)
  assert(evaluate 'value' == '42', 'cursor-selected unittest used the wrong venv')
  project_environment()
  dap.continue()
  closed()
  assert(exits[#exits] == 0, 'cursor-selected unittest ran an unrelated failing test')

  write(vim.fs.joinpath(project, 'pytest.ini'), { '[pytest]' })
  for _, runner in ipairs { 'unittest', function() return 'unittest' end } do
    python.test_runner = runner
    breakpoint(test_file, 6)
    require('custom.debug').test 'method'
    stopped(6)
    assert(evaluate 'value' == '42', 'explicit test runner used the wrong venv')
    dap.continue()
    closed()
    assert(exits[#exits] == 0, 'explicit unittest runner was overridden by project pytest markers')
  end
  python.test_runner = nil

  local exception_file = vim.fs.joinpath(project, 'exception.py')
  write(exception_file, { 'value = 42', 'raise RuntimeError("nvim2 expected failure")' })
  breakpoint(exception_file, 2)
  dap.run(vim.deepcopy(dap.configurations.python[1]))
  stopped(2)
  response(function(callback) dap.session():request('setExceptionBreakpoints', { filters = { 'uncaught' } }, callback) end)
  local reason
  dap.listeners.after.event_stopped['nvim2.checks'] = function(_, event) reason = event.reason end
  dap.continue()
  wait_for(function() return reason == 'exception' and dap.session() and dap.session().stopped_thread_id ~= nil end, 'uncaught Python exception did not stop')
  local info = response(function(callback) dap.session():request('exceptionInfo', { threadId = dap.session().stopped_thread_id }, callback) end)
  assert(info.exceptionId == 'RuntimeError', 'wrong exception reported: ' .. vim.inspect(info))
  dap.continue()
  closed()
  assert(exits[#exits] ~= 0, 'uncaught exception exited successfully')
  dap.listeners.after.event_stopped['nvim2.checks'] = nil

  local block = vim.fs.joinpath(project, 'block.py')
  write(block, { 'import os', 'import time', 'value = 42', 'time.sleep(30)' })
  breakpoint(block, 4)
  dap.run(vim.deepcopy(dap.configurations.python[1]))
  stopped(4)
  local terminated_pid = tonumber(evaluate 'os.getpid()')
  vim.fn.maparg('<leader>dq', 'n', false, true).callback()
  closed()
  wait_for(function() return not vim.uv.kill(terminated_pid, 0) end, 'terminate left the launched Python process running')

  local exit_pid_file = vim.fs.joinpath(project, 'exit-pids')
  local exit_script = vim.fs.joinpath(project, 'exit-check.lua')
  write(exit_script, {
    "vim.opt.runtimepath:prepend(vim.fn.stdpath 'config')",
    'vim.pack.add {',
    "  'https://github.com/mfussenegger/nvim-dap',",
    "  'https://github.com/mfussenegger/nvim-dap-python',",
    "  'https://github.com/nvim-neotest/nvim-nio',",
    "  'https://github.com/rcarriga/nvim-dap-ui',",
    "  'https://github.com/folke/which-key.nvim',",
    '}',
    "require('custom.debug').setup()",
    "local dap = require 'dap'",
    'vim.api.nvim_cmd({ cmd = "edit", args = { ' .. vim.json.encode(block) .. ' } }, {})',
    'vim.api.nvim_win_set_cursor(0, { 4, 0 })',
    'dap.set_breakpoint()',
    'dap.run(vim.deepcopy(dap.configurations.python[1]))',
    'assert(vim.wait(10000, function() return dap.session() and dap.session().stopped_thread_id and dap.session().current_frame end))',
    'local debuggee_pid',
    'dap.session():evaluate("os.getpid()", function(err, body) assert(not err); debuggee_pid = body.result end)',
    'assert(vim.wait(5000, function() return debuggee_pid ~= nil end))',
    'local pids = { debuggee_pid }',
    'local pid = vim.fn.getpid()',
    'for child in table.concat(vim.fn.readfile(("/proc/%d/task/%d/children"):format(pid, pid)), " "):gmatch "%d+" do',
    '  table.insert(pids, child)',
    'end',
    'assert(vim.fn.writefile(pids, ' .. vim.json.encode(exit_pid_file) .. ') == 0)',
    'vim.cmd "qa!"',
  })
  local exit_child_result
  local exit_child = vim.system(
    { vim.v.progpath, '--headless', '-u', 'NONE', '-l', exit_script },
    { text = true, timeout = 20000 },
    function(result) exit_child_result = result end
  )
  table.insert(children, exit_child)
  wait_for(function() return exit_child_result ~= nil end, 'Neovim exit did not complete with a live debug session', 20000)
  assert(exit_child_result.code == 0, 'Neovim exit fixture failed: ' .. vim.inspect(exit_child_result))
  for _, child_pid in ipairs(vim.fn.readfile(exit_pid_file)) do
    wait_for(function() return not vim.uv.kill(tonumber(child_pid), 0) end, 'Neovim exit left a launched Python/adapter process running')
  end

  local socket = assert(vim.uv.new_tcp())
  assert(socket:bind('127.0.0.1', 0))
  local port = socket:getsockname().port
  socket:close()
  local ready = vim.fs.joinpath(project, 'attach-ready')
  local finish = vim.fs.joinpath(project, 'attach-finish')
  local attach_file = vim.fs.joinpath(project, 'attach.py')
  write(attach_file, {
    'import debugpy',
    'import os',
    'import pathlib',
    'import sys',
    'import time',
    'debugpy.listen(("127.0.0.1", int(sys.argv[1])))',
    'pathlib.Path(sys.argv[2]).touch()',
    'debugpy.wait_for_client()',
    'value = 42',
    'while not pathlib.Path(sys.argv[3]).exists():',
    '    time.sleep(0.01)',
  })
  local child_result
  local child = vim.system(
    { adapter_python, '-I', '-B', '-X', 'frozen_modules=off', attach_file, tostring(port), ready, finish },
    { text = true, timeout = 30000, env = { PYTHONDONTWRITEBYTECODE = '1' } },
    function(result) child_result = result end
  )
  table.insert(children, child)
  wait_for(function() return vim.uv.fs_stat(ready) ~= nil or child_result ~= nil end, 'loopback debugpy server did not start')
  assert(not child_result, 'loopback server exited: ' .. vim.inspect(child_result))
  breakpoint(attach_file, 10)
  local attach = vim.deepcopy(dap.configurations.python[4])
  attach.connect = { host = '127.0.0.1', port = port }
  dap.run(attach)
  stopped(10)
  assert(evaluate 'value' == '42', 'attach did not expose the stopped Python frame')
  vim.fn.maparg('<leader>dd', 'n', false, true).callback()
  closed()
  assert(vim.uv.kill(child.pid, 0), 'disconnect killed the externally owned attach process')
  write(finish, { '' })
  wait_for(function() return child_result ~= nil end, 'attached process did not finish after disconnect')
  assert(child_result.code == 0, 'attached process failed: ' .. vim.inspect(child_result))
  dap.listeners.after.event_exited['nvim2.checks'] = nil
  io.stdout:write 'Nvim2 Python debugger checks passed (launch, venv, project env, variables, step, module, isolated unittest, runner overrides, exception, terminate, Neovim exit, attach)\n'
end

local ok, message = xpcall(run, debug.traceback)
if next(dap.sessions()) ~= nil then
  dap.terminate { all = true, hierarchy = true }
  vim.wait(3000, function() return next(dap.sessions()) == nil end)
end
for _, child in ipairs(children) do
  if vim.uv.kill(child.pid, 0) then child:kill(9) end
end
for _, client_id in ipairs(lsp_clients) do
  local client = vim.lsp.get_client_by_id(client_id)
  if client then client:stop(true) end
end
python.test_runner = saved_test_runner
for _, name in ipairs(environment) do
  vim.env[name] = saved_environment[name]
end
vim.fn.chdir(original_cwd)
if temporary then vim.fn.delete(temporary, 'rf') end
if not ok then
  io.stderr:write(message .. '\n')
  vim.cmd 'cquit 1'
else
  vim.cmd 'qa!'
end
