return {
  {
    "okuuva/auto-save.nvim",
    cmd = "ASToggle", -- optional for lazy loading on command
    event = { "InsertLeave", "TextChanged" }, -- optional for lazy loading on trigger events
    keys = {
      { "<leader>as", "<CMD>ASToggle<CR>", desc = "Toggle Auto-[s]ave" },
    },
    opts = {
      enabled = true,
      debounce_delay = 1000,
    },
  },
}
