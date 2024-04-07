return {
  {
    "mfussenegger/nvim-dap",
    lazy = true,
    dependencies = {
      "mfussenegger/nvim-dap-python",
      "leoluz/nvim-dap-go",
      -- { "rcarriga/nvim-dap-ui", dependencies = "nvim-neotest/nvim-nio" },
      {
        "rcarriga/nvim-dap-ui",
        dependencies = {
          -- "mfussenegger/nvim-dap",
          "nvim-neotest/nvim-nio",
        },
        -- config = function()
        --   require("dapui").setup()
        -- end,
      },

      -- "theHamsta/nvim-dap-virtual-text",
      --     "suketa/nvim-dap-ruby",
      --     config = function()
      --       require("dap-ruby").setup()
      --     end,
      --   },
      {
        "theHamsta/nvim-dap-virtual-text",
        opts = {
          highlight_changed_variables = true,
          highlight_new_as_changed = true,
          show_stop_reason = true,
          commented = true,
        },
        -- config = function(_, opts)
        --   require("nvim-dap-virtual-text").setup(opts)
        -- end,
      },
      "ofirgall/goto-breakpoints.nvim",
      {
        "LiadOz/nvim-dap-repl-highlights",
        build = ":TSInstall dap_repl",
        opts = {},
      },
    },
    keys = {
      {
        "<leader>ad",
        function()
          require("dapui").toggle()
        end,
        desc = "Toggle [D]AP UI",
      },
      {
        "<leader>dt",
        function()
          require("dap").terminate()
          require("dapui").close()
        end,
        desc = "[T]erminate",
      },
      -- { "<leader>db", ":DapToggleBreakpoint<CR>", desc = "Toggle [B]reakpoint" },
      { "<leader>dc", ":DapContinue<CR>", desc = "[C]ontinue" },
      { "<leader>dj", ":DapStepOver<CR>", desc = "[J]ump Step Over" },
      { "<leader>di", ":DapStepInto<CR>", desc = "Step [I]nto" },
      { "<leader>do", ":DapStepOut<CR>", desc = "Step [O]ut" },
      { "<leader>dr", ":DapRerun<CR>", desc = "[R]eRun" },
      { "<leader>ds", ":DapStop<CR>", desc = "[S]top" },
      { "<leader>dl", ":DapSetLogLevel TRACE<CR>", desc = "Set [L]og Level" },
    },
    config = function()
      require("dapui").setup()
      require("dap-go").setup()
      require("dap-python").setup("python3", {})

      local dap = require "dap"
      dap.adapters.bashdb = {
        type = "executable",
        command = vim.fn.stdpath "data" .. "/mason/packages/bash-debug-adapter/bash-debug-adapter",
        name = "bashdb",
      }
      dap.configurations.sh = {
        {
          type = "bashdb",
          request = "launch",
          name = "Launch file",
          showDebugOutput = true,
          pathBashdb = vim.fn.stdpath "data" .. "/mason/packages/bash-debug-adapter/extension/bashdb_dir/bashdb",
          pathBashdbLib = vim.fn.stdpath "data" .. "/mason/packages/bash-debug-adapter/extension/bashdb_dir",
          trace = true,
          file = "${file}",
          program = "${file}",
          cwd = "${workspaceFolder}",
          pathCat = "cat",
          pathBash = "/bin/bash",
          pathMkfifo = "mkfifo",
          pathPkill = "pkill",
          args = {},
          env = {},
          terminalKind = "integrated",
        },
      }
    end,
  },
  {
    "Weissle/persistent-breakpoints.nvim",
    keys = {
      { "<leader>db", ":PBToggleBreakpoint<CR>", desc = "Toggle [B]reakpoint" },
      { "<leader>dB", ":PBClearAllBreakpoints<CR>", desc = "Clear All [B]reakpoints" },
    },
    config = function()
      require("persistent-breakpoints").setup {
        load_breakpoints_event = { "BufReadPost" },
      }
    end,
  },
}
