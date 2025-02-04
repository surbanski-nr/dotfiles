return {
  {
    "olimorris/codecompanion.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    keys = {
      { "<leader>ac", mode = { "n", "v" }, "<CMD>CodeCompanionChat<CR>", desc = "Copilot [C]hat" },
    },
    opts = {
      strategies = {
        chat = {
          adapter = "copilot",
        },
        inline = {
          adapter = "copilot",
          keymaps = {
            accept_change = {
              modes = { n = "ga" },
              description = "Accept the suggested change",
            },
            reject_change = {
              modes = { n = "gr" },
              description = "Reject the suggested change",
            },
          },
        },
      },
      opts = {
        log_level = "DEBUG",
      },
    },
  },
  -- keys = {
  --   { "<leader>vt", mode = { "n", "v" }, "<CMD>CopilotChatTests<CR>", desc = "Copilot [T]ests" },
  --   { "<leader>vo", mode = { "n", "v" }, "<CMD>CopilotChatOptimize<CR>", desc = "Copilot [O]ptimize" },
  --   { "<leader>vf", mode = { "n", "v" }, "<CMD>CopilotChatFix<CR>", desc = "Copilot [F]ix Bugs" },
  --   { "<leader>vg", mode = { "n", "v" }, "<CMD>CopilotChatFixDiagnostic<CR>", desc = "Copilot fix Dia[g]nostic" },
  --   { "<leader>vd", mode = { "n", "v" }, "<CMD>CopilotChatDocs<CR>", desc = "Copilot [D]ocs" },
  --   { "<leader>vx", mode = { "n", "v" }, "<CMD>CopilotChatExplain<CR>", desc = "Copilot E[x]plain" },
  -- },
}
