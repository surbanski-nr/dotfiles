return {
  {
    "allaman/kustomize.nvim",
    dependencies = {
      { "nvim-lua/plenary.nvim" },
    },
    ft = "yaml",
    opts = { enable_key_mappings = false },
    config = function(opts)
      require("kustomize").setup { opts }
      -- default keybindings, adjust to your needs
      vim.keymap.set("n", "<leader>kb", "<cmd>lua require('kustomize').build()<cr>", { noremap = true })
      vim.keymap.set("n", "<leader>kk", "<cmd>lua require('kustomize').kinds()<cr>", { noremap = true })
      vim.keymap.set("n", "<leader>kl", "<cmd>lua require('kustomize').list_resources()<cr>", { noremap = true })
      vim.keymap.set("n", "<leader>kp", "<cmd>lua require('kustomize').print_resources()<cr>", { noremap = true })
      vim.keymap.set("n", "<leader>kv", "<cmd>lua require('kustomize').validate()<cr>", { noremap = true })
      vim.keymap.set("n", "<leader>kd", "<cmd>lua require('kustomize').deprecations()<cr>", { noremap = true })
    end,
  },
}
