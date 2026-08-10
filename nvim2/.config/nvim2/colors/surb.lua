vim.cmd 'runtime colors/default.vim'
vim.g.colors_name = 'surb'

local highlights = {
  Comment = { fg = '#7b8496', italic = true },
  Constant = { fg = '#d69c7e' },
  CursorLine = { bg = '#343842', ctermbg = 237 },
  CursorLineNr = { fg = '#ff9e64', ctermfg = 214 },
  Function = { fg = '#6fb8d9' },
  Keyword = { fg = '#c993c9' },
  MatchParen = { fg = '#ff9e64', bg = '#3f342d', ctermfg = 214, ctermbg = 237 },
  Number = { fg = '#e0a86e' },
  String = { fg = '#8fcf84' },
  Type = { fg = '#d3b66f' },
  ['@function'] = { link = 'Function' },
  ['@function.call'] = { link = 'Function' },
  ['@function.method'] = { link = 'Function' },
  ['@function.method.call'] = { link = 'Function' },
  ['@keyword'] = { link = 'Keyword' },
  ['@type'] = { link = 'Type' },
  ['@variable.member'] = { fg = '#84b7c7' },
}

for name, value in pairs(highlights) do
  vim.api.nvim_set_hl(0, name, value)
end
