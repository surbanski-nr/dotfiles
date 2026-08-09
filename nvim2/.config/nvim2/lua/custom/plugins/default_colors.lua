local default_overrides = {
  CursorLine = { bg = '#343842', ctermbg = 237 },
  CursorLineNr = { fg = '#ff9e64', ctermfg = 214 },
}

local function apply_default_overrides()
  if vim.g.colors_name ~= 'default' then return end

  for name, value in pairs(default_overrides) do
    vim.api.nvim_set_hl(0, name, value)
  end
end

apply_default_overrides()

local function capture_default_colors()
  if vim.g.colors_name ~= 'default' then return end

  local startup_highlights = vim.deepcopy(vim.api.nvim_get_hl(0, {}))
  local startup_terminal_colors = {}
  for index = 0, 15 do
    startup_terminal_colors[index] = vim.g['terminal_color_' .. index]
  end
  local startup_terminal_background = vim.g.terminal_color_background
  local startup_terminal_foreground = vim.g.terminal_color_foreground

  vim.api.nvim_create_autocmd('ColorScheme', {
    desc = 'Restore Nvim2 startup highlights after returning to default',
    group = vim.api.nvim_create_augroup('nvim2-default-colors', { clear = true }),
    pattern = 'default',
    callback = function()
      for name, value in pairs(startup_highlights) do
        local restored = vim.deepcopy(value)
        restored.default = nil
        restored.force = true
        vim.api.nvim_set_hl(0, name, restored)
      end
      for index = 0, 15 do
        vim.g['terminal_color_' .. index] = startup_terminal_colors[index]
      end
      vim.g.terminal_color_background = startup_terminal_background
      vim.g.terminal_color_foreground = startup_terminal_foreground
    end,
  })
end

vim.api.nvim_create_autocmd('VimEnter', {
  desc = 'Capture Nvim2 startup colors',
  group = vim.api.nvim_create_augroup('nvim2-capture-default-colors', { clear = true }),
  once = true,
  callback = capture_default_colors,
})
