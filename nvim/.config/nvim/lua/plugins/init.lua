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
  }
}
