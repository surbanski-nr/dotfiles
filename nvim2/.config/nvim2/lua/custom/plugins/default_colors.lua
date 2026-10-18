local class_module_color = { fg = '#c4b5fd', ctermfg = 183 } -- Soft lavender.
-- local class_module_color = { fg = '#aa8fa8', ctermfg = 139 } -- Muted plum.
-- local class_module_color = { fg = '#9994b8', ctermfg = 103 } -- Cool violet-gray.
-- local class_module_color = { fg = '#9da6b2', ctermfg = 145 } -- Neutral steel gray.

local terminal_background = { 0x14, 0x16, 0x1b }

local function shade(amount)
  local channels = {}
  for _, channel in ipairs(terminal_background) do
    channels[#channels + 1] = ('%02x'):format(math.floor(channel + (255 - channel) * amount + 0.5))
  end
  return '#' .. table.concat(channels)
end

local overrides = {
  Boolean = { fg = '#ffcaff', ctermfg = 13 },
  CursorLineNr = { fg = '#ff9e64', ctermfg = 214 },
  MatchParen = { fg = '#ff9e64', ctermfg = 214 },
  MiniStatuslineFilename = { link = 'StatusLine' },
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
  vim.api.nvim_set_hl(0, 'CursorLine', { bg = shade(0.16), ctermbg = 237 })
  vim.api.nvim_set_hl(0, 'LineNr', { fg = shade(0.40), ctermfg = 244 })
  vim.api.nvim_set_hl(0, 'StatusLine', { fg = '#e0e2ea', bg = shade(0.22), ctermfg = 255, ctermbg = 238 })
  vim.api.nvim_set_hl(0, 'StatusLineNC', { fg = '#9b9ea4', bg = shade(0.10), ctermfg = 247, ctermbg = 236 })
  -- Cursor foreground uses Normal's background, also in MiniStatusline.
  for _, name in ipairs { 'Cursor', 'lCursor' } do
    vim.api.nvim_set_hl(0, name, vim.api.nvim_get_hl(0, { name = name, link = false }))
  end
  for _, name in ipairs { 'Normal', 'NormalNC', 'WinSeparator' } do
    local highlight = vim.api.nvim_get_hl(0, { name = name, link = false })
    highlight.bg = nil
    highlight.ctermbg = nil
    vim.api.nvim_set_hl(0, name, highlight)
  end
end

apply()
local group = vim.api.nvim_create_augroup('nvim2-default-colors', { clear = true })
vim.api.nvim_create_autocmd('ColorScheme', {
  desc = 'Reapply the Nvim2 palette after a colorscheme change',
  group = group,
  callback = apply,
})
vim.api.nvim_create_autocmd('TermResponse', {
  desc = 'Adapt the cursor line, line numbers and status line to the terminal background',
  group = group,
  callback = function(event)
    local sequence = event.data.sequence
    local red, green, blue = sequence:match '^\027%]11;rgb:(%x+)/(%x+)/(%x+)$'
    if not red then
      local alpha
      red, green, blue, alpha = sequence:match '^\027%]11;rgba:(%x+)/(%x+)/(%x+)/(%x+)$'
      if not alpha or #alpha > 4 then return end
    end
    if not red or #red > 4 or #green > 4 or #blue > 4 then return end
    -- OSC 11 channels can use one to four hex digits.
    for index, channel in ipairs { red, green, blue } do
      terminal_background[index] = tonumber(channel, 16) * 255 / (16 ^ #channel - 1)
    end
    apply()
  end,
})

local function query_background() vim.api.nvim_ui_send '\027]11;?\007' end

vim.api.nvim_create_autocmd('UIEnter', {
  desc = 'Query the terminal background without waiting for a response',
  group = group,
  callback = query_background,
})
if #vim.api.nvim_list_uis() > 0 then query_background() end
