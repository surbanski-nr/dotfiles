require("nvchad.configs.lspconfig").defaults()

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
  "ts_ls",
  "nginx_language_server",
  "pyright",
}
local nvlsp = require "nvchad.configs.lspconfig"

-- lsps with default config
for _, lsp in ipairs(servers) do
  lspconfig[lsp].setup {
    on_attach = nvlsp.on_attach,
    on_init = nvlsp.on_init,
    capabilities = nvlsp.capabilities,
  }
end

lspconfig.terraformls.setup {
  on_attach = nvlsp.on_attach,
  on_init = nvlsp.on_init,
  capabilities = nvlsp.capabilities,
  filetypes = { "hcl", "tf", "terraform", "terraform-vars" },
}
