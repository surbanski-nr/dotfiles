return {
  -- :ChatGPT
  -- :ChatGPTActAs
  {
    "jackMort/ChatGPT.nvim",
    event = "VeryLazy",
    config = function()
      require("chatgpt").setup {
        api_key_cmd = "pass chatgpt/invhub-shared-oai",
        api_type_cmd = "echo azure",
        azure_api_base_cmd = "echo https://invhub-shared-oai.openai.azure.com",
        azure_api_engine_cmd = "echo gpt-4_1106-Preview",
        azure_api_version_cmd = "echo 2023-12-01-preview",
        openai_params = {
          model = "gpt-4",
          max_tokens = 4000,
        },
        openai_edit_params = {
          model = "gpt-4",
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
      { "<leader>ag", mode = { "n", "v" }, "<CMD>ChatGPT<CR>", desc = "Toggle [G]PT Chat" },
      { "<leader>ht", mode = { "n", "v" }, "<CMD>ChatGPTRun add_tests<CR>", desc = "ChatGPT Add [T]ests" },
      { "<leader>ho", mode = { "n", "v" }, "<CMD>ChatGPTRun optimize_code<CR>", desc = "ChatGPT [O]ptimize Code" },
      { "<leader>hs", mode = { "n", "v" }, "<CMD>ChatGPTRun summarize<CR>", desc = "ChatGPT [S]ummarize" },
      { "<leader>hf", mode = { "n", "v" }, "<CMD>ChatGPTRun fix_bugs<CR>", desc = "ChatGPT [F]ix Bugs" },
      { "<leader>hd", mode = { "n", "v" }, "<CMD>ChatGPTRun docstring<CR>", desc = "ChatGPT [D]ocstring" },
      { "<leader>hx", mode = { "n", "v" }, "<CMD>ChatGPTRun explain_code<CR>", desc = "ChatGPT E[X]plain Code" },
      { "<leader>he", mode = { "n", "v" }, "<CMD>ChatGPTEditWithInstructions<CR>", desc = "ChatGPT [E]dit" },
    },
  },
}
