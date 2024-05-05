return {
  "tris203/precognition.nvim",
  event = "VeryLazy",
  keys = {
    {
      "<leader>an",
      mode = { "n" },
      function()
        require("precognition").toggle()
      end,
      desc = "Toggle Precognitio[n]",
    },
  },
  config = {
    startVisible = false,
    showBlankVirtLine = false,
  },
}
