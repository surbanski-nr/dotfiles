return {
  "epwalsh/pomo.nvim",
  version = "*", -- Recommended, use latest release instead of latest commit
  -- lazy = true,
  event = "VeryLazy",
  cmd = { "TimerStart", "TimerRepeat" },
  dependencies = {
    "rcarriga/nvim-notify",
  },
  keys = {
    { "<leader>ts", ":TimerStart 25m Work<CR>:TimerHide<CR>", desc = "Timer [S]tart" },
    { "<leader>to", ":TimerStop -1<CR>", desc = "Timer [O]ff" },
    { "<leader>tp", ":TimerPause <CR>", desc = "Timer [P]ause" },
    { "<leader>tr", ":TimerResume <CR>", desc = "Timer [R]esume" },
  },
  opts = {
    {
      update_interval = 1000,
      notifiers = {
        {
          name = "Default",
          opts = {
            sticky = false,
            title_icon = "󱎫",
            text_icon = "󰄉",
          },
        },
        -- Tracking: https://github.com/epwalsh/pomo.nvim/issues/3
        { name = "System" },
      },
      timers = {
        Break = {
          { name = "System" },
        },
      },
    },
  },
}
