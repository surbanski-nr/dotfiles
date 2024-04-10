return {
  {
    "nguyenvukhang/nvim-toggler",
    event = "VeryLazy",
    config = function()
      require("nvim-toggler").setup()
    end,
    keys = {
      {
        "go",
        mode = { "n", "v" },
        function()
          require("nvim-toggler").toggle()
        end,
        desc = "T[o]ggler",
      },
    },
  },
}
