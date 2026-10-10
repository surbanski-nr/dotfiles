local dap = require 'dap'

vim.api.nvim_cmd({ cmd = 'edit', args = { vim.env.NVIM2_DEBUG_CHECK_FILE } }, {})
vim.api.nvim_win_set_cursor(0, { 4, 0 })
dap.set_breakpoint()
local config = vim.iter(dap.configurations.python):find(function(candidate) return candidate.name == 'Python: launch file' end)
dap.run(vim.deepcopy(assert(config, 'missing Python file launch')))
assert(
  vim.wait(10000, function()
    local session = dap.session()
    return session and session.stopped_thread_id and session.current_frame
  end),
  'exit fixture did not stop'
)

local debuggee_pid
dap.session():evaluate('os.getpid()', function(err, body)
  assert(not err, vim.inspect(err))
  debuggee_pid = body.result
end)
assert(vim.wait(5000, function() return debuggee_pid ~= nil end), 'exit fixture did not report its Python PID')
local pids = { debuggee_pid }
local pid = vim.fn.getpid()
for child in table.concat(vim.fn.readfile(('/proc/%d/task/%d/children'):format(pid, pid)), ' '):gmatch '%d+' do
  table.insert(pids, child)
end
assert(vim.fn.writefile(pids, vim.env.NVIM2_DEBUG_CHECK_PID_FILE) == 0, 'exit fixture could not write child PIDs')
vim.cmd 'qa!'
