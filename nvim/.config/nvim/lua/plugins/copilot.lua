return {
  -- :Copilot auth
  {
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    event = "InsertEnter",
    -- keys = {
    --   { "<leader>vt", mode = { "n", "v" }, "<CMD>CopilotChatTests<CR>", desc = "Copilot [T]ests" },
    --   { "<leader>vo", mode = { "n", "v" }, "<CMD>CopilotChatOptimize<CR>", desc = "Copilot [O]ptimize" },
    --   { "<leader>vf", mode = { "n", "v" }, "<CMD>CopilotChatFix<CR>", desc = "Copilot [F]ix Bugs" },
    --   { "<leader>vg", mode = { "n", "v" }, "<CMD>CopilotChatFixDiagnostic<CR>", desc = "Copilot fix Dia[g]nostic" },
    --   { "<leader>vd", mode = { "n", "v" }, "<CMD>CopilotChatDocs<CR>", desc = "Copilot [D]ocs" },
    --   { "<leader>vx", mode = { "n", "v" }, "<CMD>CopilotChatExplain<CR>", desc = "Copilot E[x]plain" },
    -- },
    config = function()
      require("copilot").setup {
        panel = { enabled = false },
        suggestion = {
          enabled = true,
          auto_trigger = true,
          debounce = 75,
          keymap = {
            accept = "<M-g>",
            accept_word = false,
            accept_line = false,
            next = "<M-]>",
            prev = "<M-[>",
            dismiss = "<C-]>",
          },
        },
        filetypes = {
          yaml = true,
          markdown = false,
          helm = true,
          hcl = true,
          lua = true,
        },
      }
    end,
  },
  {
    "jonahgoldwastaken/copilot-status.nvim",
    dependencies = {
      { "zbirenbaum/copilot.lua" },
    },
    lazy = false,
    -- event = "BufReadPost",
    config = function()
      require("copilot_status").setup {}
    end,
  },
}
