return {
  {
    "nvim-pack/nvim-spectre",
    cmd = "Spectre",
    opts = { open_cmd = "noswapfile vnew" },
    keys = {
      {
        "<leader>ar",
        function()
          require("spectre").toggle()
        end,
        desc = "Spect[R]e",
      },
      {
        "<leader>so",
        function()
          require("spectre").open()
        end,
        desc = "Spectre open",
      },
      {
        "<leader>sw",
        function()
          require("spectre").open_visual { select_word = true }
        end,
        desc = "Spectre open word under cursor",
      },
      {
        "<leader>sf",
        function()
          require("spectre").open_file_search { select_word = true }
        end,
        desc = "Spectre open word under cursor in current file",
      },
    },
  },
}
