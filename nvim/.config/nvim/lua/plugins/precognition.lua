return {
  "tris203/precognition.nvim",
  lazy = true,
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
