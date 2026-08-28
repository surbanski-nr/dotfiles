require('mini.align').setup()
require('mini.splitjoin').setup()

---@diagnostic disable-next-line: duplicate-set-field
require('mini.statusline').section_location = function() return '%2l/%L:%-2v %p%%' end

local visits = require 'mini.visits'
visits.setup()
local visit_opts = { sort = visits.gen_sort.default { recency_weight = 0.5 } }

vim.keymap.set('n', '<leader>vv', function() visits.select_path(vim.fn.getcwd(), visit_opts) end, { desc = '[V]isited files in cwd' })
vim.keymap.set('n', '<leader>vV', function() visits.select_path('', visit_opts) end, { desc = 'All [V]isited files' })
vim.keymap.set('n', '<leader>va', function() visits.add_label() end, { desc = '[A]dd label to current file' })
vim.keymap.set('n', '<leader>vr', function() visits.remove_label() end, { desc = '[R]emove label from current file' })
vim.keymap.set('n', '<leader>vl', function() visits.select_label('', vim.fn.getcwd(), visit_opts) end, { desc = 'Visited [L]abels in cwd' })
vim.keymap.set('n', '<leader>vL', function() visits.select_label('', '', visit_opts) end, { desc = 'All visited [L]abels' })

vim.keymap.set('n', '<C-x>', function() require('mini.bufremove').delete() end, { desc = 'Delete buffer' })

require('which-key').add {
  { '<leader>v', group = '[V]isits' },
}
