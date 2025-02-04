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
      enabled = false,
      -- enabled = function()
      --   local context = require "cmp.config.context"
      --   local disabled = false
      --   disabled = disabled or (vim.api.nvim_get_option_value("buftype", { buf = 0 }) == "prompt")
      --   disabled = disabled or (vim.fn.reg_recording() ~= "")
      --   disabled = disabled or (vim.fn.reg_executing() ~= "")
      --   disabled = disabled or (context.in_treesitter_capture "comment" or context.in_syntax_group "Comment")
      --   disabled = disabled or (vim.bo.ft ~= "markdown")
      --   return not disabled
      -- end,

      sources = {
        { name = "nvim_lsp" },
        -- { name = "copilot" },
        -- { name = "codeium" },
        { name = "luasnip" },
        { name = "buffer" },
        { name = "nvim_lua" },
        { name = "path" },
      },
    },
  },
}
