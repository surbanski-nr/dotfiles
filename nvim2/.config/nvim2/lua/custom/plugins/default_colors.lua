local class_module_color = { fg = '#c58fa3', ctermfg = 175 } -- Muted rose.
-- local class_module_color = { fg = '#aa8fa8', ctermfg = 139 } -- Muted plum.
-- local class_module_color = { fg = '#9994b8', ctermfg = 103 } -- Cool violet-gray.
-- local class_module_color = { fg = '#9da6b2', ctermfg = 145 } -- Neutral steel gray.

local overrides = {
  Boolean = { fg = '#ffcaff', ctermfg = 13 },
  CursorLine = { bg = '#343842', ctermbg = 237 },
  CursorLineNr = { fg = '#ff9e64', ctermfg = 214 },
  MatchParen = { fg = '#ff9e64', bg = '#3f342d', ctermfg = 214, ctermbg = 237 },
  Nvim2MatrixBright = { fg = '#eef1f8', ctermfg = 15 },
  Nvim2MatrixDim = { fg = '#176b66', ctermfg = 30 },
  Nvim2MatrixHead = { fg = '#8cf8f7', ctermfg = 14, bold = true },
  Nvim2MatrixMid = { fg = '#4db6ac', ctermfg = 73 },
  Number = { fg = '#ffcaff', ctermfg = 13 },
  Nvim2SearchLens = { fg = '#07080d', bg = '#fce094', ctermfg = 0, ctermbg = 11, bold = true },
  GitSignsCurrentLineBlame = { link = 'Comment' },
  Type = { fg = '#c099ff', ctermfg = 13 },
  ['@type'] = class_module_color,
  ['@type.definition'] = class_module_color,
  ['@module'] = class_module_color,
  ['@lsp.type.class'] = class_module_color,
  ['@lsp.type.namespace'] = class_module_color,
  ['@variable.member'] = { link = 'Identifier' },

  -- Comment = { fg = '#9b9ea4', italic = true },
  -- Conditional = { fg = '#c099ff', ctermfg = 13 },
  -- Constant = { fg = '#fce094', ctermfg = 11 },
  -- Function = { fg = '#8cf8f7', ctermfg = 14 },
  -- Keyword = { fg = '#e69a8d', ctermfg = 174 },
  -- Nvim2Property = { fg = '#c099ff', ctermfg = 13 },
  -- Number = { fg = '#fce094', ctermfg = 11 },
  -- Repeat = { link = 'Conditional' },
  -- Statement = { link = 'Keyword' },
  -- String = { fg = '#b3f6c0', ctermfg = 10 },
  -- ['@function'] = { link = 'Function' },
  -- ['@function.call'] = { link = 'Function' },
  -- ['@function.method'] = { link = 'Function' },
  -- ['@function.method.call'] = { link = 'Function' },
  -- ['@keyword'] = { link = 'Keyword' },
  -- ['@keyword.conditional'] = { link = 'Conditional' },
  -- ['@keyword.repeat'] = { link = 'Repeat' },
  -- ['@keyword.return'] = { link = 'Conditional' },
  -- ['@property'] = { link = 'Nvim2Property' },
  -- ['@type'] = { link = 'Type' },
  -- Type = { fg = '#a6dbff', ctermfg = 12 },
  -- ['@variable.member'] = { link = 'Nvim2Property' },
  -- Statement = { fg = '#c099ff', ctermfg = 13 },
}

local function apply()
  for name, value in pairs(overrides) do
    vim.api.nvim_set_hl(0, name, value)
  end
end

apply()
vim.api.nvim_create_autocmd('ColorScheme', {
  desc = 'Reapply the Nvim2 palette after a colorscheme change',
  group = vim.api.nvim_create_augroup('nvim2-default-colors', { clear = true }),
  callback = apply,
})
