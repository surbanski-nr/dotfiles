local M = {}

local data = vim.uv.fs_realpath(vim.fn.stdpath 'data') or vim.fn.stdpath 'data'
local packages = vim.fs.joinpath(data, 'mason', 'packages')
local release = vim.env.DOTFILES_OFFLINE_RELEASE_ROOT

function M.root()
  local file = vim.api.nvim_buf_get_name(0)
  local start = require('custom.project').canonical(file ~= '' and file or vim.fn.getcwd())
  return vim.fs.root(start, { 'pyproject.toml', 'setup.cfg', 'setup.py', '.git' }) or (file ~= '' and vim.fs.dirname(start) or start)
end

local function executable(path, label)
  if path and path ~= '' then path = vim.fn.fnamemodify(path, ':p') end
  assert(path and path ~= '' and vim.fn.executable(path) == 1, label .. ' is not executable: ' .. tostring(path))
  -- Resolving a venv Python symlink would bypass its pyvenv.cfg.
  return path
end

function M.python()
  local override = vim.b.nvim2_debug_python or vim.env.NVIM2_DEBUG_PYTHON
  if override and override ~= '' then return executable(override, 'Project Python') end
  for _, name in ipairs { 'VIRTUAL_ENV', 'CONDA_PREFIX' } do
    local prefix = vim.env[name]
    if prefix and prefix ~= '' then return executable(vim.fs.joinpath(prefix, 'bin', 'python'), name .. ' Python') end
  end

  local file = vim.api.nvim_buf_get_name(0)
  local directory = file ~= '' and vim.fs.dirname(require('custom.project').canonical(file)) or M.root()
  local boundary = require('custom.project').buffer_git_root() or M.root()
  while directory do
    for _, name in ipairs { '.venv', 'venv' } do
      local path = vim.fs.joinpath(directory, name, 'bin', 'python')
      if vim.fn.executable(path) == 1 then return path end
    end
    if directory == boundary then break end
    local parent = vim.fs.dirname(directory)
    if parent == directory then break end
    directory = parent
  end

  local fallback = release and vim.fs.joinpath(release, 'bin', 'python') or vim.fn.exepath 'python3'
  return executable(fallback, 'Python; select a project .venv or NVIM2_DEBUG_PYTHON')
end

local function launch_options(cwd, python)
  return { cwd = cwd, python = python, pythonArgs = { '-B' }, env = { PYTHONDONTWRITEBYTECODE = '1' }, console = 'integratedTerminal' }
end

local function test_runner(root)
  if vim.uv.fs_stat(vim.fs.joinpath(root, 'pytest.ini')) then return 'pytest' end
  if vim.uv.fs_stat(vim.fs.joinpath(root, 'manage.py')) then return 'django' end
  local project = vim.fs.joinpath(root, 'pyproject.toml')
  if vim.uv.fs_stat(project) then
    for _, line in ipairs(vim.fn.readfile(project)) do
      if line:match '^%s*%[tool%.pytest%.' or line:match '^%s*%[tool%.pytest%]' then return 'pytest' end
    end
  end
  return 'unittest'
end

function M.test(subject)
  local previous = vim.fn.getcwd()
  local root = M.root()
  -- dap-python resolves unittest module paths before dap.run.
  vim.fn.chdir(root)
  local ok, message = pcall(function()
    local python = require 'dap-python'
    python['test_' .. subject] {
      test_runner = python.test_runner or test_runner(root),
      config = launch_options(root, M.python()),
    }
  end)
  vim.fn.chdir(previous)
  if not ok then error(message, 0) end
end

function M.setup()
  local dap = require 'dap'
  local python = require 'dap-python'
  local ui = require 'dapui'
  local adapter_python = vim.fs.joinpath(packages, 'debugpy', 'venv', 'bin', 'python')
  python.setup(adapter_python, { include_configs = false })
  python.resolve_python = M.python
  local python_adapter = dap.adapters.python
  dap.adapters.python = function(callback, config)
    if config.request ~= 'attach' then
      executable(adapter_python, 'debugpy; run :Nvim2ToolsInstallSync')
      -- dap-python otherwise resolves .env from Neovim's cwd, not the launch cwd.
      config.envFile = config.envFile or vim.fs.joinpath(config.cwd or M.root(), '.env')
    end
    python_adapter(function(adapter)
      if adapter.type == 'executable' then adapter.args = { '-I', '-B', '-X', 'frozen_modules=off', '-m', 'debugpy.adapter' } end
      callback(adapter)
    end, config)
  end
  dap.adapters.debugpy = dap.adapters.python

  local python_launch = vim.tbl_extend('force', launch_options(M.root, M.python), { type = 'python', request = 'launch' })
  dap.configurations.python = {
    vim.tbl_extend('force', python_launch, { name = 'Python: launch file', program = '${file}' }),
    vim.tbl_extend('force', python_launch, {
      name = 'Python: launch file with arguments',
      program = '${file}',
      args = function() return require('dap.utils').splitstr(vim.fn.input 'Arguments: ') end,
    }),
    vim.tbl_extend('force', python_launch, {
      name = 'Python: launch module',
      module = function()
        local value = vim.fn.input 'Python module: '
        return value ~= '' and value or dap.ABORT
      end,
    }),
    {
      name = 'Python: attach to loopback',
      type = 'python',
      request = 'attach',
      connect = function()
        local value = vim.fn.input('Loopback port: ', '5678')
        if value == '' then return dap.ABORT end
        local port = tonumber(value)
        assert(port and port % 1 == 0 and port >= 1 and port <= 65535, 'Port must be an integer between 1 and 65535')
        return { host = '127.0.0.1', port = port }
      end,
    },
  }

  ui.setup {
    icons = { expanded = '-', collapsed = '+', current_frame = '>' },
    controls = {
      icons = {
        pause = '||',
        play = '>',
        step_into = 'v',
        step_over = '->',
        step_out = '^',
        step_back = '<-',
        run_last = '>>',
        terminate = 'X',
        disconnect = 'D',
      },
    },
  }
  dap.listeners.after.event_initialized['nvim2.ui'] = function(session)
    ui.open()
    session.on_close['nvim2.ui'] = function()
      vim.schedule(function()
        if next(dap.sessions()) == nil then ui.close() end
      end)
    end
  end

  local mappings = {
    { '<F5>', dap.continue, 'Start or continue' },
    { '<F10>', dap.step_over, 'Step over' },
    { '<F11>', dap.step_into, 'Step into' },
    { '<F12>', dap.step_out, 'Step out' },
    { '<leader>dc', dap.continue, 'Start or continue' },
    { '<leader>db', dap.toggle_breakpoint, 'Toggle breakpoint' },
    { '<leader>dB', function() dap.set_breakpoint(vim.fn.input 'Breakpoint condition: ') end, 'Conditional breakpoint' },
    { '<leader>dp', function() dap.set_breakpoint(nil, nil, vim.fn.input 'Log point message: ') end, 'Log point' },
    { '<leader>do', dap.step_over, 'Step over' },
    { '<leader>di', dap.step_into, 'Step into' },
    { '<leader>dO', dap.step_out, 'Step out' },
    { '<leader>dl', dap.run_last, 'Run last' },
    { '<leader>dq', function() dap.terminate { all = true, hierarchy = true } end, 'Terminate sessions' },
    { '<leader>dd', function() dap.disconnect { terminateDebuggee = false } end, 'Disconnect' },
    { '<leader>dr', dap.repl.toggle, 'Toggle REPL' },
    { '<leader>du', ui.toggle, 'Toggle panels' },
    { '<leader>dt', function() M.test 'method' end, 'Python test method' },
    { '<leader>dT', function() M.test 'class' end, 'Python test class' },
  }
  for _, mapping in ipairs(mappings) do
    vim.keymap.set('n', mapping[1], mapping[2], { desc = '[D]ebug: ' .. mapping[3] })
  end
  vim.keymap.set({ 'n', 'x' }, '<leader>de', ui.eval, { desc = '[D]ebug: [E]valuate expression' })
  require('which-key').add { { '<leader>d', group = '[D]ebug' } }
end

return M
