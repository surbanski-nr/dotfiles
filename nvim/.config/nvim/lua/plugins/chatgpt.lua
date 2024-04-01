return {
  -- :ChatGPT
  -- :ChatGPTActAs
  {
    "jackMort/ChatGPT.nvim",
    event = "VeryLazy",
    config = function()
      require("chatgpt").setup {
        api_key_cmd = "pass chatgpt/copilot-mvp",
        api_type_cmd = "echo azure",
        azure_api_base_cmd = "echo https://copilot-mvp.openai.azure.com",
        azure_api_engine_cmd = "echo GPT4_demo_32",
        azure_api_version_cmd = "echo 2023-12-01-preview",
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
      { "<leader>sco", "<CMD>ChatGPTRun optimize_code<CR>", desc = "ChatGPT [O]ptimize Code" },
      { "<leader>scs", "<CMD>ChatGPTRun summarize<CR>", desc = "chatGPT [S]ummarize" },
      { "<leader>scf", "<CMD>ChatGPTRun fix_bugs<CR>", desc = "ChatGPT [F]ix Bugs" },
    },
  },
}
