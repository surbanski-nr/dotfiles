local M = {}

function M.root()
  local file = vim.api.nvim_buf_get_name(0)
  local start = require('custom.project').canonical(file ~= '' and file or vim.fn.getcwd())
  return vim.fs.root(start, { 'go.mod', 'go.work', '.git' }) or (file ~= '' and vim.fs.dirname(start) or start)
end

function M.setup()
  local dap = require 'dap'
  local go = require 'dap-go'
  go.setup()
  local adapter = dap.adapters.go
  dap.adapters.go = function(callback, config)
    adapter(function(definition)
      definition = vim.deepcopy(definition)
      -- Delve builds relative packages and its temporary binary from this cwd.
      definition.executable.cwd = config.cwd or M.root()
      -- Server adapters do not accept env, so pass it through env's argv.
      definition.executable.args = require('custom.go').command(definition.executable.command, unpack(definition.executable.args))
      definition.executable.command = table.remove(definition.executable.args, 1)
      callback(definition)
    end, config)
  end

  local test_package = { name = 'Go: test package', type = 'go', request = 'launch', mode = 'test', program = '${fileDirname}' }
  dap.configurations.go = {
    { name = 'Go: launch package', type = 'go', request = 'launch', program = '${fileDirname}', cwd = M.root },
    {
      name = 'Go: launch package with arguments',
      type = 'go',
      request = 'launch',
      program = '${fileDirname}',
      cwd = M.root,
      args = function() return require('dap.utils').splitstr(vim.fn.input 'Arguments: ') end,
    },
    test_package,
  }

  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'go',
    group = vim.api.nvim_create_augroup('nvim2-debug-go', { clear = true }),
    callback = function(event)
      vim.keymap.set('n', '<leader>dt', function()
        -- dap-go otherwise turns an outside-cwd absolute path into .//absolute.
        go.debug_test { program = vim.fs.dirname(vim.api.nvim_buf_get_name(0)) }
      end, { buffer = event.buf, desc = '[D]ebug Go [T]est' })
      vim.keymap.set('n', '<leader>dT', function() dap.run(vim.deepcopy(test_package)) end, { buffer = event.buf, desc = '[D]ebug Go [T]est package' })
    end,
  })
end

return M
