return {
  -- :ChatGPT
  -- :ChatGPTActAs
  {
    "jackMort/ChatGPT.nvim",
    event = "VeryLazy",
    config = function()
      require("chatgpt").setup {
        openai_params = {
          model = "gpt-4-32k",
        },
        openai_edit_params = {
          model = "gpt-4-32k",
        },
      }
    end,
    dependencies = {
      "MunifTanjim/nui.nvim",
      "nvim-lua/plenary.nvim",
      "folke/trouble.nvim",
      "nvim-telescope/telescope.nvim",
    },
    keys = {
      { "<leader>ag", "<CMD>ChatGPT<CR>", desc = "Toggle [G]PT Chat" },
      { "<leader>sct", "<CMD>ChatGPTRun add_tests<CR>", desc = "ChatGPT Add [T]ests" },
      { "<leader>sco", "<CMD>ChatGPT optimize_code<CR>", desc = "ChatGPT [O]ptimize Code" },
      { "<leader>scs", "<CMD>ChatGPT summarize<CR>", desc = "chatGPT [S]ummarize" },
      { "<leader>scf", "<CMD>ChatGPT fix_bugs<CR>", desc = "ChatGPT [F]ix Bugs" },
    },
  },
}
