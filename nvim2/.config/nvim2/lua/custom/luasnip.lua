local M = {}

function M.setup()
  local luasnip = require 'luasnip'
  luasnip.setup {
    update_events = { 'TextChanged', 'TextChangedI' },
    delete_check_events = 'TextChanged',
    enable_autosnippets = true,
  }

  local function pair(trigger, closing)
    return luasnip.snippet({ trig = trigger, name = 'Pair ' .. trigger, snippetType = 'autosnippet', wordTrig = false }, {
      luasnip.text_node(trigger),
      luasnip.insert_node(1),
      luasnip.text_node(closing),
      luasnip.insert_node(0),
    })
  end

  luasnip.add_snippets('all', {
    pair('(', ')'),
    pair('[', ']'),
    pair('{', '}'),
    pair("'", "'"),
    pair('"', '"'),
  }, { key = 'nvim2-pairs' })
end

return M
