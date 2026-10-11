local M = {}

function M.env()
  local config = vim.env.XDG_CONFIG_HOME
  if vim.env.DOTFILES_LAUNCHER_XDG_CONFIG_HOME_SET then config = vim.env.DOTFILES_LAUNCHER_XDG_CONFIG_HOME end
  -- Go telemetry/settings and Delve config must not modify the release payload.
  return { XDG_CONFIG_HOME = config and config ~= '' and config or vim.fs.joinpath(vim.env.HOME, '.config') }
end

function M.command(...) return vim.list_extend({ 'env', 'XDG_CONFIG_HOME=' .. M.env().XDG_CONFIG_HOME }, { ... }) end

function M.with_env(callback, ...)
  local config = vim.env.XDG_CONFIG_HOME
  vim.env.XDG_CONFIG_HOME = M.env().XDG_CONFIG_HOME
  local ok, result = pcall(callback, ...)
  vim.env.XDG_CONFIG_HOME = config
  assert(ok, result)
  return result
end

function M.setup_lsp()
  local root = vim.lsp.config.gopls.root_dir
  -- lspconfig starts `go env` while finding the root, before spawning gopls.
  vim.lsp.config('gopls', { root_dir = function(...) return M.with_env(root, ...) end })
end

return M
