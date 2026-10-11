local temporary = vim.fn.tempname()
local original_path = vim.env.PATH
local original_linter = vim.env.NVIM2_REAL_GOLANGCI_LINT
local original_gate = vim.env.NVIM2_LINT_GATE
local original_go = vim.env.NVIM2_REAL_GO
local lint = require 'lint'

local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  assert(vim.fn.writefile(lines, path) == 0, 'could not write Go lint fixture: ' .. path)
end

local function run()
  if vim.env.NVIM2_CHECK_TOOLS == '0' then return end
  vim.env.GOPROXY = 'off'
  vim.env.GOTOOLCHAIN = 'local'
  vim.env.NVIM2_REAL_GOLANGCI_LINT = vim.fn.exepath 'golangci-lint'
  vim.env.NVIM2_REAL_GO = vim.fn.exepath 'go'
  local wrapper = vim.fs.joinpath(temporary, 'bin', 'golangci-lint')
  write(wrapper, vim.fn.readfile(vim.fs.joinpath(vim.fn.stdpath 'config', 'tests', 'fixtures', 'go_lint_gate.sh')))
  assert(vim.fn.setfperm(wrapper, 'rwx------') == 1, 'could not make Go lint fixture executable')
  vim.env.PATH = vim.fs.dirname(wrapper) .. ':' .. original_path
  local root = vim.fs.joinpath(temporary, 'Go lint module with spaces')
  local config = vim.fs.joinpath(root, '.golangci.yml')
  local source = vim.fs.joinpath(root, 'main.go')
  local gate = vim.fs.joinpath(temporary, 'gate')
  local namespace = lint.get_namespace 'golangcilint'
  write(vim.fs.joinpath(root, 'go.mod'), { 'module example.com/nvim2-lint', '', 'go 1.25.0' })
  write(source, { 'package main', '', 'import "os"', '', 'func main() {', '\tos.Chdir(".")', '}' })
  vim.api.nvim_cmd({ cmd = 'edit', args = { source } }, {})
  local buffer = vim.api.nvim_get_current_buf()

  local go_wrapper = vim.fs.joinpath(temporary, 'bin', 'go')
  write(go_wrapper, vim.fn.readfile(vim.fs.joinpath(vim.fn.stdpath 'config', 'tests', 'fixtures', 'go_list_gate.sh')))
  assert(vim.fn.setfperm(go_wrapper, 'rwx------') == 1, 'could not make Go package loading fixture executable')
  local other_source = vim.fs.joinpath(root, 'other.go')
  write(other_source, { 'package main', '', 'import "os"', '', 'func other() {', '\tos.Chdir(".")', '}' })
  vim.api.nvim_cmd({ cmd = 'edit', args = { other_source } }, {})
  local other_buffer = vim.api.nvim_get_current_buf()
  vim.fn.mkdir(gate, 'p')
  vim.env.NVIM2_LINT_GATE = gate
  write(config, { 'version: "2"', 'linters:', '  default: none', '  enable:', '    - errcheck' })
  vim.api.nvim_set_current_buf(buffer)
  vim.cmd 'write'
  local function loading_count() return #vim.fn.glob(vim.fs.joinpath(gate, 'loading-*'), false, true) end
  assert(vim.wait(20000, function() return loading_count() > 0 end), 'first Go linter did not reach package loading')
  vim.api.nvim_set_current_buf(other_buffer)
  vim.cmd 'write'
  assert(vim.wait(3000, function() return loading_count() > 1 end), 'second Go linter was blocked by the first runner')
  write(vim.fs.joinpath(gate, 'release'), {})
  assert(
    vim.wait(
      20000,
      function() return #vim.diagnostic.get(buffer, { namespace = namespace }) > 0 and #vim.diagnostic.get(other_buffer, { namespace = namespace }) > 0 end
    ),
    'overlapping Go linter processes did not both publish real diagnostics'
  )
  assert(vim.wait(3000, function() return #lint.get_running() == 0 end), 'concurrent Go linter processes did not finish')
  vim.fn.delete(go_wrapper)
  vim.fn.delete(gate, 'rf')
  vim.diagnostic.reset(namespace)
  vim.api.nvim_set_current_buf(buffer)

  for _, restore_config in ipairs { false, true } do
    vim.fn.mkdir(gate, 'p')
    vim.env.NVIM2_LINT_GATE = gate
    write(config, { 'version: "2"', 'linters:', '  default: none', '  enable:', '    - errcheck' })
    vim.cmd 'write'
    assert(vim.wait(20000, function() return vim.fn.filereadable(vim.fs.joinpath(gate, 'ready')) == 1 end), 'Go linter never reached the output gate')
    assert(#vim.diagnostic.get(buffer, { namespace = namespace }) == 0, 'gated Go lint result arrived early')
    vim.fn.delete(config)
    vim.cmd 'write'
    assert(#vim.diagnostic.get(buffer, { namespace = namespace }) == 0, 'removing Go lint config left diagnostics')
    if restore_config then write(config, { 'version: "2"' }) end
    write(vim.fs.joinpath(gate, 'release'), {})
    assert(vim.wait(3000, function() return #lint.get_running(buffer) == 0 end), 'gated Go lint process did not finish')
    -- Pipe publication is scheduled separately from the process-exit callback.
    assert(
      not vim.wait(200, function() return #vim.diagnostic.get(buffer, { namespace = namespace }) > 0 end),
      'a result invalidated by config removal repopulated Go diagnostics'
    )
    vim.fn.delete(gate, 'rf')
  end

  vim.env.PATH = original_path
  write(config, { 'version: "2"', 'linters:', '  default: none', '  enable:', '    - errcheck' })
  vim.cmd 'write'
  assert(
    vim.wait(20000, function()
      return vim.iter(vim.diagnostic.get(buffer, { namespace = namespace })):any(function(diagnostic) return diagnostic.source == 'errcheck' end)
    end),
    'restoring Go lint configuration did not resume diagnostics'
  )
  assert(vim.wait(3000, function() return #lint.get_running(buffer) == 0 end), 'resumed Go lint process did not finish')
  io.stdout:write 'Nvim2 Go lint checks passed (overlapping real processes, in-flight config removal, remove/recreate invalidation, resumed real diagnostics)\n'
end

local ok, message = xpcall(run, debug.traceback)
if vim.fn.isdirectory(vim.fs.joinpath(temporary, 'gate')) == 1 then write(vim.fs.joinpath(temporary, 'gate', 'release'), {}) end
vim.wait(3000, function() return #lint.get_running() == 0 end)
vim.env.PATH = original_path
vim.env.NVIM2_REAL_GOLANGCI_LINT = original_linter
vim.env.NVIM2_LINT_GATE = original_gate
vim.env.NVIM2_REAL_GO = original_go
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
