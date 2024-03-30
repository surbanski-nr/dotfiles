return {
  {
    "ahmedkhalf/project.nvim",
    event = "VeryLazy",
    config = function(_, opts)
      require("project_nvim").setup(opts)
      require("telescope").load_extension "projects"
    end,
    keys = {
      { "<leader>fp", "<Cmd>Telescope projects<CR>", desc = "Telescope [P]rojects" },
    },
  },
}
