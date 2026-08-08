local M = {}

vim.api.nvim_create_autocmd('BufWinEnter', {
  desc = 'Use native Treesitter folds in new windows',
  group = vim.api.nvim_create_augroup('nvim2-native-treesitter-folds', { clear = true }),
  callback = function(args)
    if not vim.b[args.buf].nvim2_treesitter_folds then return end
    vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
    vim.wo.foldmethod = 'expr'
  end,
})

---@param buf integer
function M.attach(buf)
  vim.b[buf].nvim2_treesitter_folds = true
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    vim.wo[win].foldexpr = 'v:lua.vim.treesitter.foldexpr()'
    vim.wo[win].foldmethod = 'expr'
    vim.wo[win].foldlevel = 99
  end
end

return M
