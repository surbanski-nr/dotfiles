local on_attach = require("nvchad.configs.lspconfig").on_attach
local on_init = require("nvchad.configs.lspconfig").on_init
local capabilities = require("nvchad.configs.lspconfig").capabilities

local lspconfig = require "lspconfig"
local servers = {
  "html",
  "cssls",
  "ansiblels",
  "bashls",
  "docker_compose_language_service",
  "dockerls",
  "gopls",
  "terraformls",
  "helm_ls",
  "marksman",
  "jsonls",
  "tsserver",
  "nginx_language_server",
  "pyright",
}

-- lsps with default config
for _, lsp in ipairs(servers) do
  lspconfig[lsp].setup {
    on_attach = on_attach,
    on_init = on_init,
    capabilities = capabilities,
  }
end
