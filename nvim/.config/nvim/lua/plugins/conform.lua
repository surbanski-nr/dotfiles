return {
  {
    "stevearc/conform.nvim",
    event = "bufwritepre", -- uncomment for format on save
    config = function()
      require "configs.conform"
    end,
  },
}
