return {
  {
    "yorickpeterse/nvim-dd",
    event = "LspAttach",
    config = function()
      require("dd").setup {
        timeout = 1000,
      }
    end,
  },
}
