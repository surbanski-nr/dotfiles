return {
  -- :Copilot auth
  {
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    event = "InsertEnter",
    keys = {
      { "<leader>sct", "<CMD>CopilotChatTests<CR>", desc = "Copilot [T]ests" },
      { "<leader>sco", "<CMD>CopilotChatOptimize<CR>", desc = "Copilot [O]ptimize" },
      { "<leader>scf", "<CMD>CopilotChatFix<CR>", desc = "Copilot [F]ix Bugs" },
      { "<leader>scd", "<CMD>CopilotChatFixDiagnostic<CR>", desc = "Copilot fix [D]iagnostic" },
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
