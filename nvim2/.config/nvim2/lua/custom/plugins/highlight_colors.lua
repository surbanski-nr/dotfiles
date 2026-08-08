local highlight_colors

vim.keymap.set('n', '<leader>tc', function()
  if not highlight_colors then
    highlight_colors = require 'nvim-highlight-colors'
    highlight_colors.setup()
  else
    highlight_colors.toggle()
  end

  local state = highlight_colors.is_active() and 'enabled' or 'disabled'
  vim.notify('Inline color previews ' .. state)
end, { desc = '[T]oggle inline [C]olors' })
