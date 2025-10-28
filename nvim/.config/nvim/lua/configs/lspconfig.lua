require("nvchad.configs.lspconfig").defaults()

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

vim.lsp.enable(servers)

vim.lsp.config("terraformls", {
  filetypes = { "hcl", "tf", "terraform", "terraform-vars" },
})
