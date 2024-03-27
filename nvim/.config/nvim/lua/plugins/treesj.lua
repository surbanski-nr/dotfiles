return {
  "Wansmer/treesj",
  keys = {
    { "<leader>sj", "<cmd>TSJToggle<cr>", desc = "Toggle Treesitter" },
  },
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
  },
  config = function()
    require("treesj").setup {}
  end,
}
