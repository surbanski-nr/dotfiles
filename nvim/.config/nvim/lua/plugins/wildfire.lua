return {
  {
    "sustech-data/wildfire.nvim",
    event = "VeryLazy",
    config = function()
      require("wildfire").setup()
    end,
  },
}
