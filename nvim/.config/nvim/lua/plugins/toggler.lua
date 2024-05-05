return {
  {
    "nguyenvukhang/nvim-toggler",
    event = "VeryLazy",
    config = function()
      require("nvim-toggler").setup {
        remove_default_keybinds = true,
      }
    end,
    keys = {
      {
        "gk",
        mode = { "n", "v" },
        function()
          require("nvim-toggler").toggle()
        end,
        desc = "T[o]ggler",
      },
    },
  },
}
