return {
  -- :Copilot auth
  {
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    event = "InsertEnter",
    keys = {
      { "<leader>sct", mode = { "n", "v" }, "<CMD>CopilotChatTests<CR>", desc = "Copilot [T]ests" },
      { "<leader>sco", mode = { "n", "v" }, "<CMD>CopilotChatOptimize<CR>", desc = "Copilot [O]ptimize" },
      { "<leader>scf", mode = { "n", "v" }, "<CMD>CopilotChatFix<CR>", desc = "Copilot [F]ix Bugs" },
      { "<leader>scg", mode = { "n", "v" }, "<CMD>CopilotChatFixDiagnostic<CR>", desc = "Copilot fix Dia[g]nostic" },
      { "<leader>scd", mode = { "n", "v" }, "<CMD>CopilotChatDocs<CR>", desc = "Copilot [D]ocs" },
      { "<leader>scx", mode = { "n", "v" }, "<CMD>CopilotChatExplain<CR>", desc = "Copilot E[x]plain" },
    },
    config = function()
      require("copilot").setup {
        suggestion = { enabled = false },
        panel = { enabled = false },
        -- filetypes = {
        --   yaml = true,
        --   helm = true,
        --   hcl = true,
        --   lua = true,
        -- },
      }
    end,
  },
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    branch = "canary",
    dependencies = {
      { "zbirenbaum/copilot.lua" }, -- or github/copilot.vim
      { "nvim-lua/plenary.nvim" }, -- for curl, log wrapper
    },
    event = "VeryLazy",
    opts = {
      debug = false,
    },
    keys = {
      { "<leader>ac", "<CMD>CopilotChatToggle<CR>", desc = "Toggle [C]opilot Chat" },
    },
    config = function()
      require("CopilotChat").setup {
        debug = true,
      }
    end,
  },
  {
    "jonahgoldwastaken/copilot-status.nvim",
    dependencies = {
      { "zbirenbaum/copilot.lua" },
    },
    lazy = true,
    event = "BufReadPost",
    config = function()
      require("copilot_status").setup {}
    end,
  },
}
