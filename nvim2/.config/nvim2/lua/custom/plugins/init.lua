local plugins_dir = vim.fs.joinpath(vim.fn.stdpath 'config', 'lua', 'custom', 'plugins')
local modules, broken_links = require('custom.plugin_loader').scan(plugins_dir)

for _, path in ipairs(broken_links) do
  local broken_path = path
  vim.schedule(function() vim.notify('Skipped broken custom plugin symlink: ' .. broken_path, vim.log.levels.WARN) end)
end

for _, module in ipairs(modules) do
  require('custom.plugins.' .. module)
end
