return {
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      {
        "zbirenbaum/copilot-cmp",
        config = function()
          require("copilot_cmp").setup()
        end,
      },
    },
    opts = {
      enabled = function()
        return (vim.bo.ft ~= "markdown")
      end,

      sources = {
        { name = "nvim_lsp" },
        { name = "copilot" },
        -- { name = "codeium" },
        { name = "luasnip" },
        { name = "buffer" },
        { name = "nvim_lua" },
        { name = "path" },
      },
    },
  },
}
