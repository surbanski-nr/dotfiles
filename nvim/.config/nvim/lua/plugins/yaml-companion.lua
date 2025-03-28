return {
  {
    -- "someone-stole-my-name/yaml-companion.nvim",
    -- "szechp/yaml-companion.nvim", -- fork that adds CRD support
    "mosheavni/yaml-companion.nvim",
    dependencies = {
      { "neovim/nvim-lspconfig" },
      { "nvim-lua/plenary.nvim" },
      { "nvim-telescope/telescope.nvim" },
    },
    config = function(_, opts)
      local cfg = require("yaml-companion").setup(opts)
      require("lspconfig")["yamlls"].setup(cfg)
      require("telescope").load_extension "yaml_schema"
    end,
  },
}
