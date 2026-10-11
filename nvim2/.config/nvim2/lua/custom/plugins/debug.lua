vim.pack.add {
  'https://github.com/mfussenegger/nvim-dap',
  'https://github.com/mfussenegger/nvim-dap-python',
  'https://github.com/leoluz/nvim-dap-go',
  'https://github.com/nvim-neotest/nvim-nio',
  'https://github.com/rcarriga/nvim-dap-ui',
}

require('custom.debug').setup()
require('custom.debug_go').setup()
