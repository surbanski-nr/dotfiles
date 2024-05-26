return {
  "gbprod/yanky.nvim",
  keys = {
    {
      "<leader>fy",
      function()
        require("telescope").extensions.yank_history.yank_history {}
      end,
      desc = "Telescope [Y]ank History",
    },
    { "y", "<Plug>(YankyYank)", mode = { "n" }, desc = "Yank text" },
    { "Y", "<Plug>(YankyYank)$", mode = { "n" }, desc = "Yank text till the end of the line" },
    { "p", "<Plug>(YankyPutAfter)", mode = { "n" }, desc = "Put yanked text after cursor" },
    { "P", "<Plug>(YankyPutBefore)", mode = { "n" }, desc = "Put yanked text before cursor" },
    { "[y", "<Plug>(YankyCycleForward)", desc = "Cycle forward through yank history" },
    { "]y", "<Plug>(YankyCycleBackward)", desc = "Cycle backward through yank history" },
  },
  opts = {
    preserve_cursor_position = {
      enabled = true,
    },
    ring = {
      history_length = 50,
    },
    highlight = {
      timer = 250,
    },
  },
}
