vim.pack.add { 'https://github.com/mfussenegger/nvim-lint' }

local lint = require 'lint'
local go_lint_runs = {}

local function lint_go(bufnr)
  local run = (go_lint_runs[bufnr] or 0) + 1
  go_lint_runs[bufnr] = run
  local path = vim.api.nvim_buf_get_name(bufnr)
  local root = vim.fs.root(path, { 'go.mod', 'go.work', '.git' })
  local config = root
    and vim.fs.find({ '.golangci.yml', '.golangci.yaml', '.golangci.toml', '.golangci.json' }, {
      path = vim.fs.dirname(path),
      upward = true,
      stop = vim.fs.dirname(vim.fs.root(path, '.git') or root),
    })[1]
  if not config then
    vim.diagnostic.reset(lint.get_namespace 'golangcilint', bufnr)
    return
  end
  -- Loading the built-in definition also runs synchronous Go/version probes.
  require('custom.go').with_env(function() return lint.linters.golangcilint end)
  lint.try_lint('golangcilint', {
    cwd = root,
    wrap_linter = function(linter)
      linter.env = vim.tbl_extend('force', vim.fn.environ(), require('custom.go').env())
      -- The built-in linter chooses file/package mode from Neovim's cwd.
      -- Always lint the buffer's package, even when launched outside its module.
      linter.args[#linter.args] = vim.fs.dirname(path)
      table.insert(linter.args, 2, '--config=' .. config)
      table.insert(linter.args, 2, '--allow-parallel-runners')
      local parser = linter.parser
      linter.parser = function(output, buffer, cwd)
        -- A save without configuration must invalidate an earlier in-flight run.
        if go_lint_runs[buffer] ~= run or not vim.uv.fs_stat(config) then return {} end
        return parser(output, buffer, cwd)
      end
      return linter
    end,
  })
end

vim.api.nvim_create_autocmd('BufWipeout', {
  group = vim.api.nvim_create_augroup('nvim2-lint-go', { clear = true }),
  callback = function(event) go_lint_runs[event.buf] = nil end,
})

local function is_github_workflow(bufnr)
  local path = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
  return path:match '/%.github/workflows/[^/]+%.ya?ml$' ~= nil
end

local eslint_filetypes = {
  javascript = true,
  javascriptreact = true,
  typescript = true,
  typescriptreact = true,
}

local eslint_configs = {
  'eslint.config.js',
  'eslint.config.mjs',
  'eslint.config.cjs',
  'eslint.config.ts',
  'eslint.config.mts',
  'eslint.config.cts',
  '.eslintrc',
  '.eslintrc.js',
  '.eslintrc.cjs',
  '.eslintrc.json',
  '.eslintrc.yaml',
  '.eslintrc.yml',
}

local function has_eslint_config(bufnr)
  if not eslint_filetypes[vim.bo[bufnr].filetype] then return false end
  local path = vim.api.nvim_buf_get_name(bufnr)
  local start = path ~= '' and vim.fs.dirname(path) or vim.fn.getcwd()
  if vim.fs.find(eslint_configs, { path = start, upward = true })[1] then return true end

  local directory = start
  while directory do
    local file = vim.fs.joinpath(directory, 'package.json')
    if vim.uv.fs_stat(file) then
      local ok, package = pcall(vim.json.decode, table.concat(vim.fn.readfile(file), '\n'))
      if ok and package.eslintConfig then return true end
    end
    local parent = vim.fs.dirname(directory)
    directory = parent ~= directory and parent or nil
  end
  return false
end

lint.linters_by_ft = {
  dockerfile = { 'hadolint' },
  javascript = { 'eslint_d' },
  javascriptreact = { 'eslint_d' },
  terraform = { 'tflint' },
  ['terraform-vars'] = { 'tflint' },
  typescript = { 'eslint_d' },
  typescriptreact = { 'eslint_d' },
  yaml = { 'yamllint' },
  ['yaml.ansible'] = { 'yamllint' },
  ['yaml.docker-compose'] = { 'yamllint' },
  ['yaml.helm-values'] = { 'yamllint' },
}

vim.api.nvim_create_autocmd('BufWritePost', {
  group = vim.api.nvim_create_augroup('nvim2-lint', { clear = true }),
  callback = function(event)
    if not vim.bo[event.buf].modifiable then return end
    vim.api.nvim_buf_call(event.buf, function()
      if vim.bo[event.buf].filetype == 'go' then
        lint_go(event.buf)
        return
      end
      lint.try_lint(nil, {
        filter = function(linter) return linter.name ~= 'eslint_d' or has_eslint_config(event.buf) end,
      })
      if is_github_workflow(event.buf) then lint.try_lint 'actionlint' end
    end)
  end,
})
