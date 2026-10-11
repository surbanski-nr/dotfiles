local dap = require 'dap'
local pids = {}
dap.listeners.after.event_process['nvim2.go-exit'] = function(_, event) pids[#pids + 1] = tostring(event.systemProcessId) end
vim.api.nvim_cmd({ cmd = 'edit', args = { vim.env.NVIM2_GO_DEBUG_FILE } }, {})
vim.api.nvim_win_set_cursor(0, { 7, 0 })
dap.set_breakpoint()
local config = vim.iter(dap.configurations.go):find(function(candidate) return candidate.name == 'Go: launch package' end)
dap.run(vim.deepcopy(assert(config, 'missing Go package launch')))
assert(
  vim.wait(15000, function()
    local session = dap.session()
    return session and session.stopped_thread_id and session.current_frame and #pids > 0
  end),
  'Go exit fixture did not stop'
)
local pid = vim.fn.getpid()
for child in table.concat(vim.fn.readfile(('/proc/%d/task/%d/children'):format(pid, pid)), ' '):gmatch '%d+' do
  pids[#pids + 1] = child
end
assert(vim.fn.writefile(pids, vim.env.NVIM2_GO_DEBUG_PID_FILE) == 0, 'Go exit fixture could not write child PIDs')
vim.cmd 'qa!'
