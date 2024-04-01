local options = {
  formatters_by_ft = {
    lua = { "stylua" },
    python = { "black" },
    javascript = { "prettier" },
    javascriptreact = { "prettier" },
    typescript = { "prettier" },
    typescriptreact = { "prettier" },
    css = { "prettier" },
    scss = { "prettier" },
    html = { "prettier" },
    json = { "jq" }, -- prettier
    jsonc = { "prettier" },
    yaml = { "yamlfix" },
    markdown = { "markdownlint" },
    graphql = { "prettier" },
    handlebars = { "prettier" },
    xml = { "xmlformatter" },
    go = { "goimports", "gofumpt" },
    sh = { "shfmt" },
    terraform = { "terraform_fmt" },
  },

  format_on_save = {
    -- These options will be passed to conform.format()
    timeout_ms = 500,
    lsp_fallback = true,
  },
}

require("conform").setup(options)
