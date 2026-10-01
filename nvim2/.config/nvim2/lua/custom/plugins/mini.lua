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
visits.setup { store = { path = vim.fs.joinpath(vim.fn.stdpath 'state', 'mini-visits-index') } }
local visit_opts = { sort = visits.gen_sort.default { recency_weight = 0.5 } }

vim.keymap.set('n', '<leader>vv', function() visits.select_path(vim.fn.getcwd(), visit_opts) end, { desc = '[V]isited files in cwd' })
vim.keymap.set('n', '<leader>vV', function() visits.select_path('', visit_opts) end, { desc = 'All [V]isited files' })
vim.keymap.set('n', '<leader>va', function() visits.add_label() end, { desc = '[A]dd label to current file' })
vim.keymap.set('n', '<leader>vr', function() visits.remove_label() end, { desc = '[R]emove label from current file' })
vim.keymap.set('n', '<leader>vl', function() visits.select_label('', vim.fn.getcwd(), visit_opts) end, { desc = 'Visited [L]abels in cwd' })
vim.keymap.set('n', '<leader>vL', function() visits.select_label('', '', visit_opts) end, { desc = 'All visited [L]abels' })

vim.keymap.set('n', '<C-x>', function() require('mini.bufremove').delete() end, { desc = 'Delete buffer' })

local function buffer_label(buffer)
  local name = vim.api.nvim_buf_get_name(buffer)
  if name == '' then return ('[No Name %d]'):format(buffer) end
  return vim.fn.fnamemodify(name, ':~:.')
end

local function remove_other_buffers(force)
  local current = vim.api.nvim_get_current_buf()
  local others = vim.iter(vim.api.nvim_list_bufs()):filter(function(buffer) return buffer ~= current and vim.fn.buflisted(buffer) == 1 end):totable()

  local blockers = vim
    .iter(others)
    :filter(function(buffer) return vim.bo[buffer].modified or vim.bo[buffer].buftype == 'terminal' end)
    :map(buffer_label)
    :totable()
  if not force and #blockers > 0 then
    vim.notify(
      'Cannot remove other buffers safely: ' .. table.concat(blockers, ', ') .. '. Save changes or stop terminals, or use :DeleteOtherBuffers! to discard them.',
      vim.log.levels.WARN
    )
    return false
  end

  local failed = {}
  local removed = 0
  local bufremove = require 'mini.bufremove'
  for _, buffer in ipairs(others) do
    if vim.api.nvim_buf_is_valid(buffer) and vim.fn.buflisted(buffer) == 1 then
      local label = buffer_label(buffer)
      local ok, result = pcall(bufremove.delete, buffer, force)
      if ok and result then
        removed = removed + 1
      else
        failed[#failed + 1] = label
      end
    end
  end

  if #failed > 0 then
    vim.notify('Could not remove buffers: ' .. table.concat(failed, ', '), vim.log.levels.ERROR)
    return false
  end

  vim.notify(('Removed %d other buffer%s'):format(removed, removed == 1 and '' or 's'))
  return true
end

vim.api.nvim_create_user_command('DeleteOtherBuffers', function(options) remove_other_buffers(options.bang) end, {
  bang = true,
  desc = 'Remove all listed buffers except the current buffer',
})
vim.keymap.set('n', '<leader>xo', function() remove_other_buffers(false) end, { desc = 'Remove all [O]ther buffers' })

require('which-key').add {
  { '<leader>v', group = '[V]isits' },
}
