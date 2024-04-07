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
  -- "golangci_lint_ls",
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

-- lspconfig["yamlls"].setup {
--   capabilities = capabilities,
--   on_attach = on_attach,
--   settings = {
--     yaml = {
--       schemas = {
--         kubernetes = "*.yaml",
--         -- ["https://raw.githubusercontent.com/instrumenta/kubernetes-json-schema/master/v1.18.0-standalone-strict/all.json"] = "/*.k8s.yaml",
--         ["http://json.schemastore.org/github-workflow"] = ".github/workflows/*",
--         ["http://json.schemastore.org/github-action"] = ".github/action.{yml,yaml}",
--         ["http://json.schemastore.org/ansible-stable-2.9"] = "roles/tasks/*.{yml,yaml}",
--         ["http://json.schemastore.org/prettierrc"] = ".prettierrc.{yml,yaml}",
--         ["http://json.schemastore.org/kustomization"] = "kustomization.{yml,yaml}",
--         ["http://json.schemastore.org/ansible-playbook"] = "*play*.{yml,yaml}",
--         ["http://json.schemastore.org/chart"] = "Chart.{yml,yaml}",
--         ["https://json.schemastore.org/dependabot-v2"] = ".github/dependabot.{yml,yaml}",
--         ["https://json.schemastore.org/gitlab-ci"] = "*gitlab-ci*.{yml,yaml}",
--         -- ["https://raw.githubusercontent.com/OAI/OpenAPI-Specification/main/schemas/v3.1/schema.json"] = "*api*.{yml,yaml}",
--         ["https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json"] = "*docker-compose*.{yml,yaml}",
--         ["https://raw.githubusercontent.com/argoproj/argo-workflows/master/api/jsonschema/schema.json"] = "*flow*.{yml,yaml}",
--       },
--     },
--   },
-- }
