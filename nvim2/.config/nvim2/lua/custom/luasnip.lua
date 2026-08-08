local M = {}

function M.setup()
  local luasnip = require 'luasnip'
  luasnip.setup {
    update_events = { 'TextChanged', 'TextChangedI' },
    delete_check_events = 'TextChanged',
    enable_autosnippets = true,
  }
  require('luasnip.loaders.from_lua').lazy_load { paths = vim.fn.stdpath 'config' .. '/snippets' }

  vim.keymap.set({ 'i', 's' }, '<C-c>', function()
    if luasnip.expandable() then
      luasnip.expand()
    elseif luasnip.choice_active() then
      luasnip.change_choice(1)
    end
  end, { silent = true, desc = 'Expand snippet or select next choice' })
end

return M
