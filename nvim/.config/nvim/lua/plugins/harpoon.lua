return {
  {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    event = "VeryLazy",
    opts = {},
    keys = {
      { "<Leader>ua", "ga", desc = "Show character under cursor" },
      {
        "<Leader>a",
        function()
          require("harpoon"):list():append()
        end,
        desc = "Add location",
      },
      {
        "<C-n>",
        function()
          require("harpoon"):list():next()
        end,
        desc = "Next location",
      },
      {
        "<C-p>",
        function()
          require("harpoon"):list():prev()
        end,
        desc = "Previous location",
      },
      {
        "<Leader>mr",
        function()
          require("harpoon"):list():remove()
        end,
        desc = "Remove location",
      },
      {
        "<Leader>1",
        function()
          require("harpoon"):list():select(1)
        end,
        desc = "Harpoon select 1",
      },
      {
        "<Leader>2",
        function()
          require("harpoon"):list():select(2)
        end,
        desc = "Harpoon select 2",
      },
      {
        "<Leader>3",
        function()
          require("harpoon"):list():select(3)
        end,
        desc = "Harpoon select 3",
      },
      {
        "<Leader>4",
        function()
          require("harpoon"):list():select(4)
        end,
        desc = "Harpoon select 4",
      },

      {
        "<Leader>lh",
        function()
          local harpoon = require "harpoon"
          if not require("lazyvim.util").has "telescope.nvim" then
            harpoon.ui:toggle_quick_menu(harpoon:list())
            return
          end
          return require "telescope._extensions.marks"()
        end,
        desc = "List locations",
      },
    },
  },
}
