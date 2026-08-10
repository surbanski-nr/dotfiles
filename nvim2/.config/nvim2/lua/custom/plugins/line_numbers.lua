local function toggle_line_number_mode()
  vim.wo.number = true
  vim.wo.relativenumber = not vim.wo.relativenumber
  vim.notify('Line numbers: ' .. (vim.wo.relativenumber and 'relative' or 'absolute'))
end

vim.keymap.set('n', '<leader>tl', toggle_line_number_mode, { desc = '[T]oggle [L]ine number mode' })
