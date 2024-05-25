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

      local path = ""

      if vim.fn.has "win32" == 1 then
        path = vim.fn.stdpath "data" .. "/mason/packages/debugpy/venv/Scripts/python"
      else
        path = vim.fn.stdpath "data" .. "/mason/packages/debugpy/venv/bin/python"
      end

      dap.adapters.python = function(cb, config)
        if config.request == "attach" then
          ---@diagnostic disable-next-line: undefined-field
          local port = (config.connect or config).port
          ---@diagnostic disable-next-line: undefined-field
          local host = (config.connect or config).host or "127.0.0.1"
          cb {
            type = "server",
            port = assert(port, "`connect.port` is required for a python `attach` configuration"),
            host = host,
            options = {
              source_filetype = "python",
            },
          }
        else
          cb {
            type = "executable",
            command = path,
            args = { "-m", "debugpy.adapter" },
            options = {
              source_filetype = "python",
            },
          }
        end
      end

      dap.configurations.python = {
        {
          -- The first three options are required by nvim-dap
          type = "python", -- the type here established the link to the adapter definition: `dap.adapters.python`
          request = "launch",
          name = "Launch file",

          -- Options below are for debugpy, see https://github.com/microsoft/debugpy/wiki/Debug-configuration-settings for supported options

          program = "${file}", -- This configuration will launch the current file if used.
          pythonPath = function()
            -- debugpy supports launching an application with a different interpreter then the one used to launch debugpy itself.
            -- The code below looks for a `venv` or `.venv` folder in the current directly and uses the python within.
            -- You could adapt this - to for example use the `VIRTUAL_ENV` environment variable.
            local cwd = vim.fn.getcwd()
            if vim.fn.executable(cwd .. "/venv/bin/python") == 1 then
              return cwd .. "/venv/bin/python"
            elseif vim.fn.executable(cwd .. "/.venv/bin/python") == 1 then
              return cwd .. "/.venv/bin/python"
            else
              return path
            end
          end,
        },
      }

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
