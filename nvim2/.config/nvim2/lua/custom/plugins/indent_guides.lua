vim.pack.add { 'https://github.com/lukas-reineke/indent-blankline.nvim' }

local indent_highlight = 'Nvim2IndentGuide'
local scope_highlight = 'Nvim2IndentScope'

local function apply_highlights()
  vim.api.nvim_set_hl(0, indent_highlight, { fg = '#4f5358', ctermfg = 239, nocombine = true })
  vim.api.nvim_set_hl(0, scope_highlight, { fg = '#e0e2ea', ctermfg = 255, nocombine = true })
end

apply_highlights()
vim.api.nvim_create_autocmd('ColorScheme', {
  desc = 'Keep Nvim2 indent guide colors after colorscheme changes',
  group = vim.api.nvim_create_augroup('nvim2-indent-guides', { clear = true }),
  callback = apply_highlights,
})

require('ibl').setup {
  indent = {
    char = '▏',
    tab_char = '▏',
    highlight = indent_highlight,
  },
  scope = {
    enabled = true,
    char = '▏',
    highlight = scope_highlight,
    show_start = false,
    show_end = false,
    -- Upstream defaults omit useful Bash and Python scopes.
    include = {
      node_type = {
        bash = { 'if_statement', 'for_statement', 'while_statement', 'case_statement', 'case_item' },
        lua = { 'table_constructor' },
        python = { 'if_statement', 'for_statement', 'while_statement', 'try_statement', 'with_statement', 'match_statement', 'case_clause' },
      },
    },
  },
}

local ibl_scope = require 'ibl.scope'
local get_scope = ibl_scope.get

-- YAML scopes end at the following dedent, which otherwise moves the active guide to column zero.
-- After updating indent-blankline, remove this wrapper if the smoke test still passes. If an
-- update breaks it, remove the wrapper and exclude `yaml` under `scope.exclude.language`; normal
-- grey YAML guides will remain, but the white active-scope guide will be disabled for YAML.
ibl_scope.get = function(bufnr, config)
  local node = get_scope(bufnr, config)
  local buffer = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  if not node or vim.bo[buffer].filetype ~= 'yaml' then return node end

  local start_row, start_col, end_row, end_col = node:range()
  if end_col ~= 0 or end_row <= start_row then return node end

  local last_row = math.min(end_row - 1, vim.api.nvim_buf_line_count(buffer) - 1)
  local last_line = vim.api.nvim_buf_get_lines(buffer, last_row, last_row + 1, false)[1] or ''
  while last_row > start_row and last_line:match '^%s*$' do
    last_row = last_row - 1
    last_line = vim.api.nvim_buf_get_lines(buffer, last_row, last_row + 1, false)[1] or ''
  end

  return {
    id = function() return node:id() end,
    type = function() return node:type() end,
    start = function() return start_row, start_col end,
    end_ = function() return last_row, #last_line end,
    range = function() return start_row, start_col, last_row, #last_line end,
  }
end

vim.keymap.set('n', '<leader>ti', '<Cmd>IBLToggle<CR>', { desc = '[T]oggle [I]ndent guides' })
