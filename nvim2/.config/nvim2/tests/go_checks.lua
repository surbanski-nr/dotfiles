local temporary = vim.fn.tempname()
local clients = {}

local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  assert(vim.fn.writefile(lines, path) == 0, 'could not write Go fixture: ' .. path)
end

local function command(args, cwd)
  local env = vim.tbl_extend('force', require('custom.go').env(), { GOPROXY = 'off', GOTOOLCHAIN = 'local' })
  local result = vim.system(args, { cwd = cwd, text = true, env = env }):wait(30000)
  assert(result.code == 0, table.concat(args, ' ') .. ': ' .. (result.stderr or ''))
  return vim.trim(result.stdout or '')
end

local function run()
  if vim.env.NVIM2_CHECK_TOOLS == '0' then return end
  vim.env.GOPROXY = 'off'
  vim.env.GOTOOLCHAIN = 'local'
  local root = vim.fs.joinpath(temporary, 'Go module with spaces')
  vim.fn.mkdir(root, 'p')
  command { 'git', 'init', '-q', root }
  write(vim.fs.joinpath(root, 'go.mod'), { 'module example.com/nvim2-check', '', 'go 1.25.0' })
  write(vim.fs.joinpath(root, 'main.go'), { 'package main', '', 'func main(){', 'fmt.Println(answer())', '}' })
  write(vim.fs.joinpath(root, 'answer.go'), { 'package main', '', 'func answer() int { return 42 }' })
  local file = vim.fs.joinpath(root, 'main.go')
  vim.api.nvim_cmd({ cmd = 'edit', args = { file } }, {})
  local buffer = vim.api.nvim_get_current_buf()
  assert(vim.bo.filetype == 'go', 'Go filetype was not detected')
  assert(vim.wait(15000, function() return vim.treesitter.highlighter.active[buffer] ~= nil end), 'Go Treesitter did not attach')

  local function gopls() return vim.lsp.get_clients({ bufnr = buffer, name = 'gopls' })[1] end
  assert(vim.wait(15000, function() return gopls() ~= nil end), 'gopls did not attach')
  clients[#clients + 1] = gopls().id
  assert(vim.wait(15000, function() return #vim.diagnostic.get(buffer) > 0 end), 'gopls did not report the missing import')
  local original = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  vim.cmd 'write'
  assert(vim.deep_equal(vim.fn.readfile(file), original), 'goimports changed imports/content before opt-in')
  vim.cmd 'FormatEnable!'
  vim.cmd 'write'
  local formatted = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), '\n')
  assert(
    formatted:find('import "fmt"', 1, true) and formatted:find('\tfmt.Println(answer())', 1, true),
    'goimports did not format and add the import: ' .. formatted
  )
  assert(command({ 'go', 'run', '.' }, root) == '42', 'formatted multi-file package did not run')
  command({ 'go', 'test', './...' }, root)

  vim.api.nvim_win_set_cursor(0, { 6, 14 })
  local definition = gopls():request_sync('textDocument/definition', vim.lsp.util.make_position_params(0, gopls().offset_encoding), 10000, buffer)
  assert(definition and definition.result and #definition.result > 0, 'gopls returned no definition for answer')
  local target = definition.result[1].uri or definition.result[1].targetUri
  assert(vim.uri_to_fname(target) == vim.fs.joinpath(root, 'answer.go'), 'gopls resolved the wrong definition')
  local hover = gopls():request_sync('textDocument/hover', vim.lsp.util.make_position_params(0, gopls().offset_encoding), 10000, buffer)
  assert(hover and hover.result and hover.result.contents, 'gopls returned no hover for answer')
  vim.api.nvim_win_set_cursor(0, { 6, 5 })
  local completion = gopls():request_sync('textDocument/completion', vim.lsp.util.make_position_params(0, gopls().offset_encoding), 10000, buffer)
  assert(
    completion and completion.result and vim.iter(completion.result.items or completion.result):any(function(item) return item.label == 'Println' end),
    'gopls returned no fmt.Println completion'
  )

  local dependency = vim.fs.joinpath(temporary, 'local-dependency')
  local vendored = vim.fs.joinpath(temporary, 'vendored-module')
  write(vim.fs.joinpath(dependency, 'go.mod'), { 'module example.com/local-dependency', '', 'go 1.25.0' })
  write(vim.fs.joinpath(dependency, 'answer.go'), { 'package answer', '', 'const Value = 42' })
  write(vim.fs.joinpath(vendored, 'go.mod'), {
    'module example.com/vendored',
    '',
    'go 1.25.0',
    '',
    'require example.com/local-dependency v0.0.0',
    'replace example.com/local-dependency => ../local-dependency',
  })
  write(vim.fs.joinpath(vendored, 'main.go'), {
    'package main',
    'import ("fmt"; answer "example.com/local-dependency")',
    'func main() { fmt.Println(answer.Value) }',
  })
  command({ 'go', 'mod', 'vendor' }, vendored)
  vim.fn.delete(dependency, 'rf')
  assert(command({ 'go', 'run', '-mod=vendor', '.' }, vendored) == '42', 'vendored dependency did not work without its source or network')

  local namespace = require('lint').get_namespace 'golangcilint'
  assert(#vim.diagnostic.get(buffer, { namespace = namespace }) == 0, 'Go linter ran without project configuration')
  write(vim.fs.joinpath(root, '.golangci.yml'), { 'version: "2"', 'linters:', '  default: none', '  enable:', '    - errcheck' })
  write(file, { 'package main', '', 'import "os"', '', 'func main() {', '\tos.Chdir(".")', '}' })
  vim.cmd 'edit!'
  local other_file = vim.fs.joinpath(root, 'answer.go')
  write(other_file, { 'package main', '', 'import "os"', '', 'func answer() int {', '\tos.Chdir(".")', '\treturn 42', '}' })
  vim.api.nvim_cmd({ cmd = 'edit', args = { other_file } }, {})
  local other_buffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_set_current_buf(buffer)
  vim.cmd 'write'
  vim.api.nvim_set_current_buf(other_buffer)
  vim.cmd 'write'
  assert(
    vim.wait(20000, function()
      for _, candidate in ipairs { buffer, other_buffer } do
        if not vim.iter(vim.diagnostic.get(candidate, { namespace = namespace })):any(function(diagnostic) return diagnostic.source == 'errcheck' end) then
          return false
        end
      end
      return true
    end),
    'concurrent Go buffer saves did not both receive golangci-lint diagnostics'
  )
  assert(vim.wait(3000, function() return #require('lint').get_running() == 0 end), 'Go lint processes did not finish')
  vim.fn.delete(vim.fs.joinpath(root, '.golangci.yml'))
  vim.api.nvim_set_current_buf(buffer)
  vim.cmd 'write'
  assert(#vim.diagnostic.get(buffer, { namespace = namespace }) == 0, 'removing Go lint config left stale diagnostics')

  for _, case in ipairs {
    { 'go.mod', 'gomod' },
    { 'go.sum', 'gosum' },
    { 'go.work', 'gowork' },
  } do
    local path = vim.fs.joinpath(root, case[1])
    if case[1] == 'go.sum' then write(path, {}) end
    if case[1] == 'go.work' then write(path, { 'go 1.25.0', '', 'use .' }) end
    vim.api.nvim_cmd({ cmd = 'edit', args = { path } }, {})
    assert(vim.bo.filetype == case[2], 'incorrect Go manifest filetype: ' .. case[1])
    assert(
      vim.wait(3000, function() return vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()] ~= nil end),
      'manifest parser did not attach: ' .. case[1]
    )
  end
  io.stdout:write 'Nvim2 Go checks passed (SDK, package run/test, offline vendor, gopls diagnostics/definition/hover/completion, goimports on save, concurrent async lint, manifest parsers)\n'
end

local ok, message = xpcall(run, debug.traceback)
for _, id in ipairs(clients) do
  local client = vim.lsp.get_client_by_id(id)
  if client then client:stop(true) end
end
vim.fn.delete(temporary, 'rf')
if not ok then
  io.stderr:write(message .. '\n')
  vim.cmd 'cquit 1'
else
  vim.cmd 'qa!'
end
