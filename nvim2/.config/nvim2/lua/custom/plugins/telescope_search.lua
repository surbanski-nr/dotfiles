local M = {}

local builtin = require 'telescope.builtin'
local excluded_patterns = { '^%.git/', '/%.git/', '^node_modules/', '/node_modules/' }
local hidden_grep_args = { '--hidden', '--glob', '!**/.git/*', '--glob', '!**/node_modules/*' }

---@return string[]?
local function hidden_file_command()
  for _, executable in ipairs { 'fd', 'fdfind' } do
    if vim.fn.executable(executable) == 1 then return { executable, '--type', 'f', '--hidden', '--exclude', '.git', '--exclude', 'node_modules' } end
  end

  if vim.fn.executable 'rg' == 1 then return { 'rg', '--files', '--hidden', '--glob', '!**/.git/*', '--glob', '!**/node_modules/*' } end
end

---@param opts? table
---@return table
function M.file_options(opts)
  local find_command = hidden_file_command()
  return vim.tbl_extend('force', {
    hidden = find_command == nil,
    no_ignore = false,
    find_command = find_command,
    file_ignore_patterns = excluded_patterns,
  }, opts or {})
end

---@return string[]
function M.grep_args() return vim.deepcopy(hidden_grep_args) end

---@param opts? table
---@return table
function M.grep_options(opts)
  return vim.tbl_extend('force', {
    additional_args = M.grep_args(),
    file_ignore_patterns = excluded_patterns,
  }, opts or {})
end

---@param opts? table
function M.find_files(opts) builtin.find_files(M.file_options(opts)) end

---@param opts? table
function M.live_grep(opts) builtin.live_grep(M.grep_options(opts)) end

require('telescope').setup {
  pickers = {
    find_files = M.file_options(),
    live_grep = M.grep_options(),
  },
}

---@param bufnr? integer
---@return string
function M.nearest_git_root(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr or 0)
  local start = path ~= '' and vim.fs.dirname(path) or vim.uv.cwd()
  return vim.fs.root(start, '.git') or vim.fn.getcwd()
end

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

vim.keymap.set('n', '<leader>sf', M.find_files, { desc = '[S]earch [F]iles' })
vim.keymap.set('n', '<leader>sg', M.live_grep, { desc = '[S]earch by [G]rep' })

vim.keymap.set('n', '<leader>sF', function()
  local root = M.nearest_git_root()
  M.find_files { cwd = root, prompt_title = 'Find Files: ' .. root }
end, { desc = '[S]earch [F]iles in nearest Git root' })

vim.keymap.set('n', '<leader>sG', function()
  local root = M.nearest_git_root()
  M.live_grep { cwd = root, prompt_title = 'Live Grep: ' .. root }
end, { desc = '[S]earch by [G]rep in nearest Git root' })

return M
