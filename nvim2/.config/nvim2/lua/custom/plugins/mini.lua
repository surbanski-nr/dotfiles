require('mini.align').setup()
require('mini.splitjoin').setup()

local jump2d = require 'mini.jump2d'
jump2d.setup { mappings = { start_jumping = '' } }
vim.keymap.set('n', '<leader>j', function()
  local window = vim.api.nvim_get_current_win()
  local config = vim.api.nvim_win_get_config(window)
  if vim.bo.buftype ~= '' or vim.bo.filetype == 'neo-tree' or config.relative ~= '' then
    vim.notify('Character jump is available in ordinary editing windows', vim.log.levels.INFO)
    return
  end
  -- The builtin input hook mutates this exact table before Mini computes spots.
  local opts = jump2d.builtin_opts.single_character
  local allowed_windows = opts.allowed_windows
  opts.spotter = function() return {} end
  opts.allowed_windows = { current = true, not_current = false }
  local ok, message = pcall(jump2d.start, opts)
  opts.allowed_windows = allowed_windows
  if not ok then error(message, 0) end
end, { desc = '[J]ump to visible character' })

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
