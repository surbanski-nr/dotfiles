return {
  {
    "hrsh7th/nvim-cmp",
    opts = {
      enabled = function()
        return (vim.bo.ft ~= "markdown")
      end,
      sources = {
        -- Copilot Source
        { name = "copilot", group_index = 2 },
        -- Other Sources
        { name = "nvim_lsp", group_index = 2 },
        { name = "path", group_index = 2 },
        { name = "luasnip", group_index = 2 },
      },
    },
  },
}