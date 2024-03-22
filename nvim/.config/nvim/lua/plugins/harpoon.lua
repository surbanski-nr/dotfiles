return {
  {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    event = "VeryLazy",
    opts = {},
    keys = {
      {
        "<Leader>a",
        function()
          require("harpoon"):list():append()
        end,
        desc = "Add location - Harpoon",
      },
      {
        "<C-n>",
        function()
          require("harpoon"):list():next()
        end,
        desc = "Next location - Harpoon",
      },
      {
        "<C-p>",
        function()
          require("harpoon"):list():prev()
        end,
        desc = "Previous location - Harpoon",
      },
      {
        "<Leader>mr",
        function()
          require("harpoon"):list():remove()
        end,
        desc = "Remove location - Harpoon",
      },
      {
        "<Leader>1",
        function()
          require("harpoon"):list():select(1)
        end,
        desc = "Harpoon select 1 - Harpoon",
      },
      {
        "<Leader>2",
        function()
          require("harpoon"):list():select(2)
        end,
        desc = "Harpoon select 2 - Harpoon",
      },
      {
        "<Leader>3",
        function()
          require("harpoon"):list():select(3)
        end,
        desc = "Harpoon select 3 - Harpoon",
      },
      {
        "<Leader>4",
        function()
          require("harpoon"):list():select(4)
        end,
        desc = "Harpoon select 4 - Harpoon",
      },

      {
        "<Leader>lh",
        function()
          local harpoon = require "harpoon"

          -- REQUIRED
          harpoon:setup()
          -- REQUIRED

          local conf = require("telescope.config").values
          local function toggle_telescope(harpoon_files)
            local file_paths = {}
            for _, item in ipairs(harpoon_files.items) do
              table.insert(file_paths, item.value)
            end

            require("telescope.pickers")
              .new({}, {
                prompt_title = "Harpoon",
                finder = require("telescope.finders").new_table {
                  results = file_paths,
                },
                previewer = conf.file_previewer {},
                sorter = conf.generic_sorter {},
              })
              :find()
          end
          return toggle_telescope(harpoon:list())
        end,
        desc = "List locations - Harpoon",
      },
    },
  },
}
