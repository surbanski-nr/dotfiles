local M = {}

local function expand(body) vim.snippet.expand(body) end

local markdown_bodies = {
  bold = '**${1}**$0',
  bold_italic = '**_${1}_**$0',
  fence = '```${1:lang}\n${2}\n```$0',
  italic = '_${1}_$0',
  strikethrough = '~~${1}~~$0',
  url = '<${1}>$0',
}

function M.expand_markdown(name) expand(assert(markdown_bodies[name], 'unknown Markdown snippet: ' .. name)) end

local function add_pair(opening, closing)
  vim.keymap.set('i', opening, function() expand(opening .. '${1}' .. closing .. '$0') end, {
    desc = 'Insert matching ' .. opening .. closing,
  })
end

local function text_before_cursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  return vim.api.nvim_get_current_line():sub(1, cursor[2])
end

local function add_markdown_triggers(key, definitions)
  vim.keymap.set('i', key, function()
    local before = text_before_cursor()
    for _, definition in ipairs(definitions) do
      if before:sub(-#definition.prefix) == definition.prefix then
        local command = ("<Cmd>lua require('custom.plugins.snippets').expand_markdown('%s')<CR>"):format(definition.name)
        return ('<BS>'):rep(#definition.prefix) .. command
      end
    end

    return key
  end, { buffer = true, desc = 'Expand Markdown snippet', expr = true })
end

function M.setup()
  add_pair('(', ')')
  add_pair('[', ']')
  add_pair('{', '}')
  add_pair("'", "'")
  add_pair('"', '"')

  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'markdown',
    callback = function()
      add_markdown_triggers('`', { { prefix = '``', name = 'fence' } })
      add_markdown_triggers('*', { { prefix = '*', name = 'bold' } })
      add_markdown_triggers('_', {
        { prefix = '_', name = 'italic' },
        { prefix = '*', name = 'bold_italic' },
      })
      add_markdown_triggers('~', { { prefix = '~', name = 'strikethrough' } })
      add_markdown_triggers('<', { { prefix = '<', name = 'url' } })
    end,
  })
end

M.setup()

return M
