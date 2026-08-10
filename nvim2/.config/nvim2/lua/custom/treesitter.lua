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
  'mermaid',
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

vim.api.nvim_create_autocmd('BufWinEnter', {
  desc = 'Use native Treesitter folds in new windows',
  group = vim.api.nvim_create_augroup('nvim2-native-treesitter-folds', { clear = true }),
  callback = function(args)
    if not vim.b[args.buf].nvim2_treesitter_folds then return end
    vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
    vim.wo.foldmethod = 'expr'
  end,
})

function M.attach_folds(buf)
  vim.b[buf].nvim2_treesitter_folds = true
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    vim.wo[win].foldexpr = 'v:lua.vim.treesitter.foldexpr()'
    vim.wo[win].foldmethod = 'expr'
    vim.wo[win].foldlevel = 99
  end
end

local function maintain_parsers()
  local treesitter = require 'nvim-treesitter'
  treesitter.install(M.parsers):wait(300000)
  treesitter.update(M.parsers):wait(300000)
end

function M.setup_tools_command()
  vim.api.nvim_create_user_command('Nvim2ToolsInstallSync', function()
    vim.cmd 'MasonToolsInstallSync'
    if vim.fn.executable 'tree-sitter' ~= 1 then error 'Mason did not install tree-sitter-cli' end
    maintain_parsers()
  end, { desc = 'Install Mason tools and Treesitter parsers synchronously' })
end

return M
