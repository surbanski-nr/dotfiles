vim.pack.add { 'https://github.com/lukas-reineke/indent-blankline.nvim' }

local indent_highlight = 'Nvim2IndentGuide'
local scope_highlight = 'Nvim2IndentScope'

local function apply_highlights()
  vim.api.nvim_set_hl(0, indent_highlight, { fg = '#4f5358', ctermfg = 239, nocombine = true })
  vim.api.nvim_set_hl(0, scope_highlight, { fg = '#e0e2ea', ctermfg = 255, nocombine = true })
end

apply_highlights()
vim.api.nvim_create_autocmd('ColorScheme', {
  desc = 'Keep Nvim2 indent guide colors after colorscheme changes',
  group = vim.api.nvim_create_augroup('nvim2-indent-guides', { clear = true }),
  callback = apply_highlights,
})

require('ibl').setup {
  indent = {
    char = '▏',
    tab_char = '▏',
    highlight = indent_highlight,
  },
  scope = {
    enabled = true,
    char = '▏',
    highlight = scope_highlight,
    show_start = false,
    show_end = false,
    include = { node_type = { lua = { 'table_constructor' } } },
  },
}

vim.keymap.set('n', '<leader>ti', '<Cmd>IBLToggle<CR>', { desc = '[T]oggle [I]ndent guides' })
