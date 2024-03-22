return {
  {
    "olimorris/persisted.nvim",
    lazy = false, -- make sure the plugin is always loaded at startup
    config = true,
    -- event = "VimEnter",
    -- opts = {
    --   autosave = true, -- automatically save session files when exiting Neovim
    --   autoload = true, -- automatically load the session for the cwd on Neovim startup
    --   on_autoload_no_session = function()
    --     vim.notify "No existing session to load."
    --   end,
    --   telescope = { -- options for the telescope extension
    --     reset_prompt_after_deletion = true, -- whether to reset prompt after session deleted
    --   },
    --   config = function(_, opts)
    --     -- vim.o.sessionoptions = "buffers,curdir,folds,globals,tabpages,winpos,winsize"
    --     require("persisted").setup(opts)
    --     require("telescope").load_extension "persisted"
    --   end,
    -- },
  },
}
