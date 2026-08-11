local function select_parent() vim.treesitter.select 'parent' end
local function select_child() vim.treesitter.select 'child' end

vim.keymap.set({ 'n', 'x' }, '<C-Space>', select_parent, { desc = 'Start or expand Treesitter selection' })
vim.keymap.set('x', '<BS>', select_child, { desc = 'Shrink Treesitter selection' })
