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
        desc = "Harpoon Add location",
      },
      {
        "<C-n>",
        function()
          require("harpoon"):list():next()
        end,
        desc = "Harpoon Next location",
      },
      {
        "<C-p>",
        function()
          require("harpoon"):list():prev()
        end,
        desc = "Harpoon Previous location",
      },
      {
        "<Leader>mr",
        function()
          require("harpoon"):list():remove()
        end,
        desc = "Harpoon Remove location",
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
        "<Leader>5",
        function()
          require("harpoon"):list():select(5)
        end,
        desc = "Harpoon select 5",
      },
      {
        "<Leader>6",
        function()
          require("harpoon"):list():select(6)
        end,
        desc = "Harpoon select 6",
      },
      {
        "<Leader>7",
        function()
          require("harpoon"):list():select(7)
        end,
        desc = "Harpoon select 7",
      },
      {
        "<Leader>8",
        function()
          require("harpoon"):list():select(8)
        end,
        desc = "Harpoon select 8",
      },
      {
        "<Leader>9",
        function()
          require("harpoon"):list():select(9)
        end,
        desc = "Harpoon select 9",
      },
      {
        "<Leader>fr",
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
        desc = "Telescope Ha[r]poon",
      },
    },
  },
}
