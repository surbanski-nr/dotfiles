--`<C-]>` CD
-- `<C-k>` Info
-- `<C-r>` Rename: Omit Filename
-- `<C-v>` Open: Vertical Split
-- `<BS>`  Close Directory
-- `-` Up
--`E` Expand All
--`F`  Live Filter: Clear
-- `f` Live Filter: Start
-- `g?` Help
-- `gy` Copy Absolute Path
-- `ge` Copy Basename
-- `H`  Toggle Filter: Dotfiles
-- `I`  Toggle Filter: Git Ignore
--`R` Refresh
--`y` Copy Name
--`Y` Copy Relative Path
return {
  {
    "nvim-tree/nvim-tree.lua",
    opts = {
      git = {
        enable = true,
      },
      renderer = {
        root_folder_label = true,
      },
      view = {
        adaptive_size = true,
      },
      update_focused_file = {
        enable = true,
        update_root = true,
      },
    },
  },
}
