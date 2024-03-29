return {
  "folke/trouble.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  keys = {
    { "<leader>at", "<cmd>TroubleToggle document_diagnostics<cr>", desc = "Toggle Trouble" },
    { "<leader>aw", "<cmd>TroubleToggle workspace_diagnostics<cr>", desc = "Toggle Trouble in [W]orkspace" },
  },
  opts = {},
}
