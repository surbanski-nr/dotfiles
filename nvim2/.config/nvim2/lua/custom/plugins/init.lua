vim.pack.add {
  'https://github.com/folke/persistence.nvim',
  'https://github.com/MeanderingProgrammer/render-markdown.nvim',
  'https://github.com/brenoprata10/nvim-highlight-colors',
}

-- Iterate over all Lua files in the plugins directory and load them
local plugins_dir = vim.fs.joinpath(vim.fn.stdpath 'config', 'lua', 'custom', 'plugins')
for file_name, entry_type in vim.fs.dir(plugins_dir, { follow = true }) do
  if (entry_type == 'file' or entry_type == 'link') and file_name:match '%.lua$' and file_name ~= 'init.lua' then
    local module = file_name:gsub('%.lua$', '')
    require('custom.plugins.' .. module)
  end
end
