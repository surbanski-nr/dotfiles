local builtin = require 'telescope.builtin'

vim.keymap.set(
  'n',
  '<leader>/',
  function()
    builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
      winblend = 0,
      previewer = false,
    })
  end,
  { desc = '[/] Fuzzily search in current buffer' }
)

---@param bufnr? integer
---@return string
local function nearest_git_root(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr or 0)
  local start = path ~= '' and vim.fs.dirname(path) or vim.uv.cwd()
  return vim.fs.root(start, '.git') or vim.fn.getcwd()
end

vim.keymap.set('n', '<leader>sF', function()
  local root = nearest_git_root()
  builtin.find_files { cwd = root, prompt_title = 'Find Files: ' .. root }
end, { desc = '[S]earch [F]iles in nearest Git root' })

vim.keymap.set('n', '<leader>sG', function()
  local root = nearest_git_root()
  builtin.live_grep { cwd = root, prompt_title = 'Live Grep: ' .. root }
end, { desc = '[S]earch by [G]rep in nearest Git root' })
