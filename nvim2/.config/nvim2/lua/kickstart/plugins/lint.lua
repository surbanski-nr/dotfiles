-- Linting

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

-- Create autocommand which carries out the actual linting
-- on the specified events.
local lint_augroup = vim.api.nvim_create_augroup('lint', { clear = true })
vim.api.nvim_create_autocmd('BufWritePost', {
  group = lint_augroup,
  callback = function()
    -- Only run the linter in buffers that you can modify in order to
    -- avoid superfluous noise, notably within the handy LSP pop-ups that
    -- describe the hovered symbol using Markdown.
    if vim.bo.modifiable then lint.try_lint() end
  end,
})
