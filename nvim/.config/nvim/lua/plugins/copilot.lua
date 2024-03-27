return {
  -- :Copilot auth
  {
    "zbirenbaum/copilot.lua",

    cmd = "Copilot",
    -- build = ":Copilot auth",
    event = "InsertEnter",
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
      debug = false, -- Enable debugging
    },
    config = function()
      require("CopilotChat").setup {
        debug = true, -- Enable debugging
      }
    end,
  },
}
