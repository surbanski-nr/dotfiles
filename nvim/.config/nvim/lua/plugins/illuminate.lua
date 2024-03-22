return {
  {
    "RRethy/vim-illuminate",
    event = "CursorHold",
    config = function()
      require("illuminate").configure {
        providers = {
          "lsp",
          "treesitter",
          "regex",
        },
        filetypes_denylist = {
          -- "dirbuf",
          -- "dirvish",
          -- "fugitive",
          "NvimTree",
        },
      }
    end,
  },
}
