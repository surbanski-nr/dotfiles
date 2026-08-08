local M = {}

---@type table<string, vim.lsp.Config>
M.servers = {
  ansiblels = {},
  bashls = {},
  cssls = {},
  docker_language_server = {},
  helm_ls = {},
  jsonls = {},
  markdown_oxide = {},
  pyright = {},
  ruff = {
    on_attach = function(client) client.server_capabilities.hoverProvider = false end,
  },
  taplo = {},
  terraformls = {
    -- Older 0.12 development builds lack the API used by lspconfig's default callback.
    on_attach = function(_, bufnr)
      if vim.lsp.codelens.enable then vim.lsp.codelens.enable(true, { bufnr = bufnr }) end
    end,
  },
  yamlls = {
    settings = {
      redhat = { telemetry = { enabled = false } },
      yaml = { format = { enable = false } },
    },
  },
  lua_ls = {
    on_init = function(client)
      client.server_capabilities.documentFormattingProvider = false

      if client.workspace_folders then
        local path = client.workspace_folders[1].name
        if path ~= vim.fn.stdpath 'config' and (vim.uv.fs_stat(path .. '/.luarc.json') or vim.uv.fs_stat(path .. '/.luarc.jsonc')) then return end
      end

      local current_settings = client.config.settings --[[@as lspconfig.settings.lua_ls]]
      client.config.settings.Lua = vim.tbl_deep_extend('force', current_settings.Lua, {
        runtime = {
          version = 'LuaJIT',
          path = { 'lua/?.lua', 'lua/?/init.lua' },
        },
        workspace = {
          checkThirdParty = false,
          library = vim.tbl_extend('force', vim.api.nvim_get_runtime_file('', true), {
            '${3rd}/luv/library',
            '${3rd}/busted/library',
          }),
        },
      })
    end,
    settings = {
      Lua = {
        format = { enable = false },
      },
    },
  },
}

function M.setup_tools()
  require('mason-tool-installer').setup {
    ensure_installed = {
      { 'ansible-language-server', version = '1.2.3' },
      { 'ansible-lint', version = '26.1.1' },
      { 'bash-language-server', version = '5.6.0' },
      { 'css-lsp', version = '4.10.0' },
      { 'docker-language-server', version = 'v0.20.1' },
      { 'hadolint', version = 'v2.15.1' },
      { 'helm-ls', version = 'v0.5.4' },
      { 'json-lsp', version = '4.10.0' },
      { 'lua-language-server', version = '3.17.1' },
      { 'markdown-oxide', version = 'v0.25.12' },
      { 'prettier', version = '3.9.6' },
      { 'pyright', version = '1.1.408' },
      { 'ruff', version = '0.16.1' },
      { 'shellcheck', version = 'v0.11.0' },
      { 'shfmt', version = 'v3.13.1' },
      { 'stylua', version = 'v2.3.1' },
      { 'taplo', version = '0.10.0' },
      { 'terraform-ls', version = 'v0.38.3' },
      { 'tflint', version = 'v0.64.0' },
      { 'tree-sitter-cli', version = 'v0.26.11' },
      { 'yaml-language-server', version = '1.19.2' },
      { 'yamlfmt', version = 'v0.21.0' },
      { 'yamllint', version = '1.38.0' },
    },
    auto_update = false,
    run_on_start = false,
  }
end

return M
