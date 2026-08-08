vim.pack.add { 'https://github.com/folke/persistence.nvim' }

local persistence = require 'persistence'

persistence.setup()
vim.keymap.set('n', '<leader>pw', persistence.save, { desc = '[W]rite session' })
vim.keymap.set('n', '<leader>pr', persistence.load, { desc = '[R]estore session' })
vim.keymap.set('n', '<leader>ps', persistence.select, { desc = '[S]elect session' })
