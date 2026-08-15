local M = {}

local builtin = require 'telescope.builtin'
local excluded_patterns = { '^%.git/', '/%.git/', '^node_modules/', '/node_modules/' }
local hidden_grep_args = { '--hidden', '--glob', '!**/.git/*', '--glob', '!**/node_modules/*' }

local function hidden_file_command()
  for _, executable in ipairs { 'fd', 'fdfind' } do
    if vim.fn.executable(executable) == 1 then return { executable, '--type', 'f', '--hidden', '--exclude', '.git', '--exclude', 'node_modules' } end
  end

  if vim.fn.executable 'rg' == 1 then return { 'rg', '--files', '--hidden', '--glob', '!**/.git/*', '--glob', '!**/node_modules/*' } end
end

function M.file_options(opts)
  local find_command = hidden_file_command()
  return vim.tbl_extend('force', {
    hidden = find_command == nil,
    no_ignore = false,
    find_command = find_command,
    file_ignore_patterns = excluded_patterns,
  }, opts or {})
end

function M.grep_args() return vim.deepcopy(hidden_grep_args) end

function M.grep_options(opts)
  return vim.tbl_extend('force', {
    additional_args = M.grep_args(),
    file_ignore_patterns = excluded_patterns,
  }, opts or {})
end

function M.find_files(opts) builtin.find_files(M.file_options(opts)) end

function M.live_grep(opts) builtin.live_grep(M.grep_options(opts)) end

function M.promote_yank(register)
  local index = tonumber(register)
  if not index or index < 1 or index > 9 then error 'yank history register must be between 1 and 9' end

  local selected = vim.fn.getreginfo(tostring(index))
  for destination = index, 2, -1 do
    vim.fn.setreg(tostring(destination), vim.fn.getreginfo(tostring(destination - 1)))
  end
  vim.fn.setreg('1', selected)
  vim.fn.setreg('"', selected)
end

function M.yank_history(opts)
  opts = opts or {}
  local registers = {}
  for index = 1, 9 do
    local register = tostring(index)
    if vim.fn.getreg(register, 1) ~= '' then registers[#registers + 1] = register end
  end
  if #registers == 0 then
    vim.notify('Yank history is empty', vim.log.levels.INFO)
    return
  end

  local actions = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'
  local conf = require('telescope.config').values
  require('telescope.pickers')
    .new(opts, {
      prompt_title = 'Yank history',
      finder = require('telescope.finders').new_table {
        results = registers,
        entry_maker = require('telescope.make_entry').gen_from_registers(opts),
      },
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          if not selection then return end
          actions.close(prompt_bufnr)
          M.promote_yank(selection.value)
        end)
        return true
      end,
    })
    :find()
end

function M.nearest_git_root()
  local path = vim.api.nvim_buf_get_name(0)
  local start = path ~= '' and vim.fs.dirname(path) or vim.uv.cwd()
  return vim.fs.root(start, '.git') or vim.fn.getcwd()
end

function M.setup()
  require('telescope').setup {
    pickers = {
      find_files = M.file_options(),
      live_grep = M.grep_options(),
    },
    extensions = {
      ['ui-select'] = { require('telescope.themes').get_dropdown() },
    },
  }
  require('telescope').load_extension 'ui-select'

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
  vim.keymap.set('n', '<leader>sq', builtin.quickfix, { desc = '[S]earch [Q]uickfix list' })
  vim.keymap.set('n', '<leader>sl', builtin.loclist, { desc = '[S]earch [L]ocation list' })
  vim.keymap.set('n', '<leader>sj', builtin.jumplist, { desc = '[S]earch [J]ump list' })
  vim.keymap.set('n', '<leader>sm', builtin.marks, { desc = '[S]earch [M]arks' })
  vim.keymap.set('n', '<leader>sy', M.yank_history, { desc = '[S]earch [Y]ank history' })
  vim.keymap.set('n', '<leader>sF', function()
    local root = M.nearest_git_root()
    M.find_files { cwd = root, prompt_title = 'Find Files: ' .. root }
  end, { desc = '[S]earch [F]iles in nearest Git root' })
  vim.keymap.set('n', '<leader>sG', function()
    local root = M.nearest_git_root()
    M.live_grep { cwd = root, prompt_title = 'Live Grep: ' .. root }
  end, { desc = '[S]earch by [G]rep in nearest Git root' })
end

return M
