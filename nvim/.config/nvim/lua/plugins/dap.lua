return {
  {
    "mfussenegger/nvim-dap",
    lazy = true,
    dependencies = {
      "mfussenegger/nvim-dap-python",
      "leoluz/nvim-dap-go",
      { "rcarriga/nvim-dap-ui", dependencies = "nvim-neotest/nvim-nio" },
      "theHamsta/nvim-dap-virtual-text",
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
      { "<leader>db", ":DapToggleBreakpoint<CR>", desc = "Toggle [B]reakpoint" },
      { "<leader>dc", ":DapContinue<CR>", desc = "[C]ontinue" },
      { "<leader>dj", ":DapStepOver<CR>", desc = "[J]ump Step Over" },
      { "<leader>di", ":DapStepInto<CR>", desc = "Step [I]nto" },
      { "<leader>do", ":DapStepOut<CR>", desc = "Step [O]ut" },
      { "<leader>dr", ":DapRerun<CR>", desc = "[R]eRun" },
      { "<leader>dl", ":DapSetLogLevel TRACE<CR>", desc = "Set [L]og Level" },
    },
    config = function()
      require("dap-go").setup()
      require("dap-python").setup("python3", {})
    end,
  },
  {
    "rcarriga/nvim-dap-ui",
    dependencies = {
      "mfussenegger/nvim-dap",
      "nvim-neotest/nvim-nio",
    },
    config = function()
      require("dapui").setup()
    end,
  },
}
