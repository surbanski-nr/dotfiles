return {
  {
    "ahmedkhalf/project.nvim",
    event = "VeryLazy",
    config = function()
      require("project_nvim").setup {
        detection_methods = { "pattern" },
      }
      require("telescope").load_extension "projects"
    end,
    keys = {
      { "<leader>fp", "<Cmd>Telescope projects<CR>", desc = "Telescope [P]rojects" },
    },
  },
}
