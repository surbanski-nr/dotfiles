return {
  {
    "stevearc/conform.nvim",
    config = function()
      require "configs.conform"
    end,
  },

  {
    "nvim-tree/nvim-tree.lua",
    opts = {
      git = { enable = true },
    },
  },

  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        -- defaults 
        "vim",
        "lua",
        "vimdoc",

        -- devops
        "bash",
        "tmux",
        "dockerfile",
        "helm",
        "terraform",
        "bicep",
        "groovy",
        "go",
        "python",

        -- productivity
        "markdown",
        "xml",
        "yaml",
        "regex",
        "json",
        "jq",
        "sql",
        "comment",
        "diff",

        -- web dev 
        "html",
        "css",
        "javascript",
        "typescript",
        "tsx",

       -- low level
        "c",
        "zig"
      },
    },
  },

  {
    "williamboman/mason.nvim",
    opts = {
      ensure_installed = {
        "lua-language-server",
        "html-lsp",
        "prettier",
        "stylua",
        "ansible-language-server",
        "ansible-lint",
        "bash-language-server",
        "cfn-lint",
        "docker-compose-language-service",
        "dockerfile-language-server",
        "groovy-language-server",
        "helm-ls",
        "htmlbeautifier",
        "jq",
        "jq-lsp",
        "json-lsp",
        "jsonlint",
        "markdownlint",
        "nginx-language-server",
        "pylint",
        "python-lsp-server",
        "shellcheck",
        "shellharden",
        "snyk",
        "snyk-ls",
        "sql-formatter",
        "sqlfluff",
        "sqlls",
        "terraform-ls",
        "trivy",
        "typescript-language-server",
        "xmlformatter",
        "yaml-language-server",
        "yamlfix",
        "yamllint",
        "yq"
      },
    },
  },

  {
    "neovim/nvim-lspconfig",
    ---@class PluginLspOpts
    opts = {
      servers = {
        -- pyright will be automatically installed with mason and loaded with lspconfig
        -- pyright = {},
        bashls = {},
        -- gopls = {},
        bicep = {},
        yamlls = {},
        marksman = {},
        powershell_es = {},
        -- azure_pipelines_ls = {},
        terraformls = {},
        helm_ls = {},
      },
    },
  },

}
