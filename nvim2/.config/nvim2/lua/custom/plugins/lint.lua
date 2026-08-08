vim.pack.add { 'https://github.com/mfussenegger/nvim-lint' }

local lint = require 'lint'
lint.linters_by_ft = {
  dockerfile = { 'hadolint' },
  terraform = { 'tflint' },
  ['terraform-vars'] = { 'tflint' },
  yaml = { 'yamllint' },
  ['yaml.ansible'] = { 'yamllint' },
  ['yaml.docker-compose'] = { 'yamllint' },
  ['yaml.helm-values'] = { 'yamllint' },
}

vim.api.nvim_create_autocmd('BufWritePost', {
  group = vim.api.nvim_create_augroup('nvim2-lint', { clear = true }),
  callback = function()
    if vim.bo.modifiable then lint.try_lint() end
  end,
})
