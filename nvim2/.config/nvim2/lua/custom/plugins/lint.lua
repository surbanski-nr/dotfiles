vim.pack.add { 'https://github.com/mfussenegger/nvim-lint' }

local lint = require 'lint'

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
      lint.try_lint(nil, {
        filter = function(linter) return linter.name ~= 'eslint_d' or has_eslint_config(event.buf) end,
      })
      if is_github_workflow(event.buf) then lint.try_lint 'actionlint' end
    end)
  end,
})
