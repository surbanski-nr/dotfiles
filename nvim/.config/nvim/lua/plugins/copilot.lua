return {
  {
    "zbirenbaum/copilot.lua",

    cmd = "Copilot",
    -- build = ":Copilot auth",
    event = "InsertEnter",
    config = function()
      require("copilot").setup {
        suggestion = { enabled = false },
        panel = { enabled = false },
        filetypes = {
          yaml = true,
          helm = true,
          hcl = true,
          lua = true,
        },
      }
    end,
  },
  {
    "zbirenbaum/copilot-cmp",
    config = function()
      require("copilot_cmp").setup()
    end,
  },
  { "AndreM222/copilot-lualine" },
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    branch = "canary",
    dependencies = {
      { "zbirenbaum/copilot.lua" }, -- or github/copilot.vim
      { "nvim-lua/plenary.nvim" }, -- for curl, log wrapper
    },
    opts = {
      debug = true, -- Enable debugging
      -- See Configuration section for rest
    },
    config = function()
      require("CopilotChat").setup {
        debug = true, -- Enable debugging
        -- See Configuration section for rest
      }
    end,
    -- See Commands section for default commands if you want to lazy load on them
  },
}
