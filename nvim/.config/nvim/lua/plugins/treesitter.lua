return {
  {
    "nvim-treesitter/nvim-treesitter",
    dependencies = {
      "windwp/nvim-ts-autotag",
    },
    opts = {
      autotag = {
        enable = true,
      },
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
        "hcl",
        "bicep",
        "groovy",
        "go",
        "python",

        -- productivity
        "markdown",
        "markdown_inline",
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
        "zig",
      },
    },
  },
}
