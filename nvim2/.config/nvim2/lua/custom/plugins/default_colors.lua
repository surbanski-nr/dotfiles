local overrides = {
  CursorLine = { bg = '#343842', ctermbg = 237 },
  CursorLineNr = { fg = '#ff9e64', ctermfg = 214 },
  MatchParen = { fg = '#ff9e64', bg = '#3f342d', ctermfg = 214, ctermbg = 237 },
}

local function apply()
  if vim.g.colors_name ~= 'default' then return end

  for name, value in pairs(overrides) do
    vim.api.nvim_set_hl(0, name, value)
  end
end

apply()
vim.api.nvim_create_autocmd('ColorScheme', {
  desc = 'Apply Nvim2 default colors',
  group = vim.api.nvim_create_augroup('nvim2-default-colors', { clear = true }),
  pattern = 'default',
  callback = apply,
})
