return {
  {
    -- navigate your code with search labels
    "folke/flash.nvim",
    event = "VeryLazy",
    ---@type Flash.Config
    opts = {},
  -- stylua: ignore
    keys = {
    { "ss", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash Word" },
    { "st", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
    { "<leader>sr", mode = "o", function() require("flash").remote() end, desc = "Remote Flash" },
    { "<leader>su", mode = { "o", "x" }, function() require("flash").treesitter_search() end, desc = "Treesitter Search" },
    -- { "<leader>sS", mode = { "c" }, function() require("flash").toggle() end, desc = "Toggle Flash Search" },
    },
  },
}
