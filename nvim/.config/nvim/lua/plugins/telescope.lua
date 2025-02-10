return {
  {
    "nvim-telescope/telescope.nvim",
    config = function()
      require("telescope").setup {
        pickers = {
          live_grep = {
            file_ignore_patterns = {
              "node_modules",
              ".git/",
              ".venv",
            },
            additional_args = function(_)
              return { "--hidden" }
            end,
          },
          find_files = {
            file_ignore_patterns = {
              "node_modules",
              ".git/",
              ".venv",
            },
            hidden = true,
          },
        },
        -- extensions = {
        --   "fzf",
        -- },
      }
      -- telescope.load_extension "fzf"
    end,
  },
}
