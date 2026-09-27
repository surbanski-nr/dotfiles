local function run()
  if vim.env.NVIM2_CHECK_TOOLS == '0' then
    io.stdout:write 'Nvim2 language checks skipped because tools are disabled\n'
    return
  end

  local function write(path, lines)
    vim.fn.mkdir(vim.fs.dirname(path), 'p')
    assert(vim.fn.writefile(lines, path) == 0, 'could not write language fixture: ' .. path)
  end

  local temporary = vim.fn.tempname()
  local generic_yaml_root = vim.fn.tempname()
  vim.fn.mkdir(temporary, 'p')
  vim.fn.mkdir(generic_yaml_root, 'p')
  vim.fn.system { 'git', 'init', '-q', temporary }
  assert(vim.v.shell_error == 0, 'could not initialize the language fixture repository')

  write(vim.fs.joinpath(temporary, '.luarc.json'), { '{}' })
  write(vim.fs.joinpath(temporary, 'package.json'), { '{"private":true}' })
  write(vim.fs.joinpath(temporary, 'tsconfig.json'), { '{"compilerOptions":{"strict":true,"jsx":"react-jsx"}}' })
  write(vim.fs.joinpath(temporary, 'ansible.cfg'), { '[defaults]', 'inventory = hosts' })
  write(vim.fs.joinpath(temporary, 'Chart.yaml'), { 'apiVersion: v2', 'name: nvim2-check', 'version: 0.1.0' })

  local fixtures = {
    {
      path = 'sample.lua',
      filetype = 'lua',
      clients = { 'lua_ls' },
      parser = 'lua',
      lines = { 'local  value={answer=42}', 'return value' },
      formatted = 'local value = { answer = 42 }',
    },
    {
      path = 'sample.py',
      filetype = 'python',
      clients = { 'pyright', 'ruff' },
      parser = 'python',
      lines = { 'def greet( name:str)->str:', ' return name', '', 'print(missing_name)' },
      formatted = 'def greet(name: str) -> str:',
      diagnostic = true,
    },
    {
      path = 'sample.sh',
      filetype = 'sh',
      clients = { 'bashls' },
      parser = 'bash',
      lines = { '#!/usr/bin/env bash', 'if true;then echo yes;fi' },
      formatted = 'if true; then echo yes; fi',
      formatted_line = 2,
    },
    {
      path = 'sample.ts',
      filetype = 'typescript',
      clients = { 'ts_ls' },
      parser = 'typescript',
      lines = { 'const typed:number="wrong";', 'const label="hello";', 'label.to' },
      formatted = 'const typed: number = "wrong";',
      diagnostic = true,
      completion = true,
    },
    {
      path = 'sample.tsx',
      filetype = 'typescriptreact',
      clients = { 'ts_ls' },
      parser = 'tsx',
      lines = { 'export const App=()=> <div>ok</div>' },
      formatted = 'export const App = () => <div>ok</div>;',
    },
    {
      path = 'main.tf',
      filetype = 'terraform',
      clients = { 'terraformls' },
      parser = 'terraform',
      lines = { 'terraform {', 'required_version = ">= 1.0"', '}' },
      codelens = true,
    },
    {
      path = 'playbooks/site.yml',
      filetype = 'yaml.ansible',
      clients = { 'ansiblels' },
      parser = 'yaml',
      lines = { '- hosts: all', '  tasks:', '    - debug:', '        msg: hello' },
      formatter = true,
    },
    {
      path = 'templates/deployment.yaml',
      filetype = 'helm',
      clients = { 'helm_ls' },
      parser = 'helm',
      lines = { 'apiVersion: v1', 'kind: ConfigMap', 'metadata:', '  name: {{ .Release.Name }}' },
    },
    {
      path = vim.fs.joinpath(generic_yaml_root, 'config.yaml'),
      filetype = 'yaml',
      clients = { 'yamlls' },
      parser = 'yaml',
      lines = { 'name: value', 'items:', ' - one' },
      formatter = true,
    },
  }

  local function client_named(bufnr, name)
    return vim.iter(vim.lsp.get_clients { bufnr = bufnr }):find(function(client) return client.name == name end)
  end

  for _, fixture in ipairs(fixtures) do
    local path = fixture.path:sub(1, 1) == '/' and fixture.path or vim.fs.joinpath(temporary, fixture.path)
    write(path, fixture.lines)
    vim.api.nvim_cmd({ cmd = 'edit', args = { path } }, {})
    local buffer = vim.api.nvim_get_current_buf()
    assert(vim.bo[buffer].filetype == fixture.filetype, ('%s detected as %s instead of %s'):format(fixture.path, vim.bo[buffer].filetype, fixture.filetype))
    for _, name in ipairs(fixture.clients) do
      assert(vim.wait(15000, function() return client_named(buffer, name) ~= nil end), ('%s did not attach to %s'):format(name, fixture.path))
    end
    assert(vim.wait(3000, function() return vim.treesitter.highlighter.active[buffer] ~= nil end), 'Treesitter did not highlight ' .. fixture.path)
    assert(vim.wo.foldmethod == 'expr' and vim.wo.foldexpr == 'v:lua.vim.treesitter.foldexpr()', 'Treesitter folds did not attach to ' .. fixture.path)

    if fixture.formatted then
      require('conform').format { bufnr = buffer, async = false, timeout_ms = 10000 }
      local formatted_line = fixture.formatted_line or 1
      assert(
        vim.api.nvim_buf_get_lines(buffer, formatted_line - 1, formatted_line, false)[1] == fixture.formatted,
        ('formatter produced unexpected output for %s: %s'):format(fixture.path, vim.inspect(vim.api.nvim_buf_get_lines(buffer, 0, -1, false)))
      )
    elseif fixture.formatter then
      local available = vim.iter(require('conform').list_formatters(buffer)):any(function(formatter) return formatter.available end)
      assert(available, 'no configured formatter is available for ' .. fixture.path)
      require('conform').format { bufnr = buffer, async = false, timeout_ms = 10000 }
    end

    if fixture.completion then
      vim.api.nvim_win_set_cursor(0, { 3, 8 })
      local client = client_named(buffer, 'ts_ls')
      local response = client:request_sync('textDocument/completion', vim.lsp.util.make_position_params(0, client.offset_encoding), 10000, buffer)
      local result = response and response.result
      local items = result and (result.items or result)
      assert(type(items) == 'table' and #items > 0, 'TypeScript LSP returned no completion items')
    end

    if fixture.diagnostic then
      assert(vim.wait(15000, function() return #vim.diagnostic.get(buffer) > 0 end), 'LSP produced no expected diagnostic for ' .. fixture.path)
    end

    if fixture.codelens then
      local client = client_named(buffer, 'terraformls')
      assert(client:supports_method('textDocument/codeLens', buffer), 'Terraform LSP no longer advertises codelens support')
      assert(vim.lsp.codelens.is_enabled { bufnr = buffer }, 'nvim-lspconfig did not enable Terraform codelens on Neovim 0.12.5')
    end

    vim.bo[buffer].modified = false
    vim.api.nvim_buf_delete(buffer, { force = true })
  end

  vim.fn.delete(temporary, 'rf')
  vim.fn.delete(generic_yaml_root, 'rf')
  io.stdout:write 'Nvim2 language checks passed\n'
end

local ok, error_message = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(error_message .. '\n')
  vim.cmd 'cquit 1'
else
  vim.cmd 'qa!'
end
