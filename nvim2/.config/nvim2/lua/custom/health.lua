local M = {}

function M.check()
  vim.health.start 'Nvim2 custom configuration'
  for _, result in ipairs(require('custom.checks').run()) do
    local message = ('%s: %s'):format(result.name, result.detail)
    if result.ok then
      vim.health.ok(message)
    else
      vim.health.error(message)
    end
  end
end

return M
