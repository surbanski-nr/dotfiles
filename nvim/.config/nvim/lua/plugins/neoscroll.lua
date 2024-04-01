return {
  "karb94/neoscroll.nvim",
  keys = { "<C-d>", "<C-u>" },
  config = function()
    require("neoscroll").setup {
      mappings = {
        "<C-u>",
        "<C-d>",
      },
    }
  end,
}
