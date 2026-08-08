local M = {}

M.parsers = {
  'bash',
  'css',
  'dockerfile',
  'hcl',
  'helm',
  'json',
  'lua',
  'markdown',
  'markdown_inline',
  'python',
  'query',
  'terraform',
  'toml',
  'vim',
  'vimdoc',
  'yaml',

  -- 'c',
  -- 'diff',
  -- 'git_config',
  -- 'gitignore',
  -- 'html',
  -- 'javascript',
  -- 'luadoc',
  -- 'regex',
  -- 'scss',
  -- 'svelte',
  -- 'typescript',
  -- 'vue',
}

local function maintain_parsers()
  if vim.fn.executable 'tree-sitter' ~= 1 then return end

  local treesitter = require 'nvim-treesitter'
  treesitter.install(M.parsers):wait(300000)
  treesitter.update(M.parsers):wait(300000)
end

function M.setup_tools_command()
  vim.api.nvim_create_user_command('Nvim2ToolsInstallSync', function()
    local mason_ok, mason_error = pcall(vim.cmd, 'MasonToolsInstallSync')
    if not mason_ok then error(mason_error) end
    if vim.fn.executable 'tree-sitter' ~= 1 then error 'Mason did not install tree-sitter-cli' end
    maintain_parsers()
  end, { desc = 'Install Mason tools and Treesitter parsers synchronously' })
end

return M
