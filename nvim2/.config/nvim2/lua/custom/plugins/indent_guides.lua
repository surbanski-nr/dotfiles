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
        yaml = { 'block_mapping_pair', 'block_sequence_item' },
      },
    },
    -- Generic YAML block nodes select different scopes on sibling keys.
    exclude = { node_type = { yaml = { 'block_node' } } },
  },
}

local ibl_scope = require 'ibl.scope'
local get_scope = ibl_scope.get
local yaml_scope

-- YAML scopes end at the following dedent, which otherwise moves the active guide to column zero.
-- After updating indent-blankline, remove this wrapper if the smoke test still passes. If an
-- update breaks it, remove the wrapper and exclude `yaml` under `scope.exclude.language`; normal
-- grey YAML guides will remain, but the white active-scope guide will be disabled for YAML.
ibl_scope.get = function(bufnr, config)
  yaml_scope = nil
  local node = get_scope(bufnr, config)
  local buffer = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  if not node or vim.treesitter.language.get_lang(vim.bo[buffer].filetype) ~= 'yaml' then return node end

  local start_row, start_col, end_row, end_col = node:range()
  local start_line = vim.api.nvim_buf_get_lines(buffer, start_row, start_row + 1, false)[1] or ''
  if start_col > #(start_line:match '^%s*') then
    local left_offset = require('ibl.utils').get_offset(buffer)
    yaml_scope = { buffer = buffer, column = start_col - left_offset }
  end
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

local hooks = require 'ibl.hooks'
-- For `- settings:`, ibl places the guide before the dash rather than under the key.
hooks.register(hooks.type.VIRTUAL_TEXT, function(_, buffer, _, virtual_text)
  if not yaml_scope or yaml_scope.buffer ~= buffer then return virtual_text end
  local target = virtual_text[yaml_scope.column + 1]
  if not target then return virtual_text end
  for _, chunk in ipairs(virtual_text) do
    local highlights = type(chunk[2]) == 'table' and chunk[2] or { chunk[2] }
    if vim.tbl_contains(highlights, '@ibl.scope.char.1') then
      chunk[2] = { '@ibl.indent.char.1' }
      target[1], target[2] = '▏', { '@ibl.scope.char.1' }
      break
    end
  end
  return virtual_text
end)

vim.keymap.set('n', '<leader>ti', '<Cmd>IBLToggle<CR>', { desc = '[T]oggle [I]ndent guides' })
