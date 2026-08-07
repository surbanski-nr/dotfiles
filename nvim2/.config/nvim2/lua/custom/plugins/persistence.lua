local persistence = require 'persistence'

persistence.setup()
vim.keymap.set('n', '<leader>pr', persistence.load, { desc = '[R]estore session' })
vim.keymap.set('n', '<leader>ps', persistence.select, { desc = '[S]elect session' })
