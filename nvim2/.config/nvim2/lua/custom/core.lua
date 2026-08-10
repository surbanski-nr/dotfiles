vim.g.have_nerd_font = true

vim.o.relativenumber = true
vim.o.mouse = ''
vim.o.winborder = 'rounded'
vim.o.wrap = true
vim.o.showbreak = '↪ '
vim.opt.listchars = { extends = '…', nbsp = '␣', precedes = '…', tab = '> ', trail = '·' }
vim.o.scrolloff = 15
vim.o.foldmethod = 'marker'
vim.o.foldmarker = '{{{,}}}'
vim.o.foldlevel = 99
vim.o.foldlevelstart = 99

if vim.env.SSH_CONNECTION then
  local function paste_from_register() return vim.split(vim.fn.getreg '"', '\n') end

  vim.g.clipboard = {
    name = 'OSC 52',
    copy = {
      ['+'] = require('vim.ui.clipboard.osc52').copy '+',
      ['*'] = require('vim.ui.clipboard.osc52').copy '*',
    },
    paste = {
      ['+'] = paste_from_register,
      ['*'] = paste_from_register,
    },
  }
end

local function yaml_filetype(path)
  local normalized = vim.fs.normalize(path)
  local filename = vim.fs.basename(normalized)

  if
    filename:match '^docker%-compose.*%.yaml$'
    or filename:match '^docker%-compose.*%.yml$'
    or filename:match '^compose.*%.yaml$'
    or filename:match '^compose.*%.yml$'
  then
    return 'yaml.docker-compose'
  end

  local chart_root = vim.fs.root(normalized, { 'Chart.yaml' })
  if chart_root then
    if normalized:find('/templates/', 1, true) then return 'helm' end
    if filename:match '^values.*%.yaml$' or filename:match '^values.*%.yml$' then return 'yaml.helm-values' end
  end

  if vim.fs.root(normalized, { 'ansible.cfg', '.ansible-lint' }) then return 'yaml.ansible' end
  if normalized:match '/playbooks/' then return 'yaml.ansible' end
  for _, directory in ipairs { 'defaults', 'handlers', 'meta', 'tasks', 'vars' } do
    if normalized:match('/roles/[^/]+/' .. directory .. '/') then return 'yaml.ansible' end
  end
end

vim.filetype.add {
  pattern = {
    ['.*%.yaml'] = yaml_filetype,
    ['.*%.yml'] = yaml_filetype,
    ['.*/templates/.*%.tpl'] = function(path)
      if vim.fs.root(path, { 'Chart.yaml' }) then return 'helm' end
    end,
  },
}

vim.keymap.set('n', 'c', '"_c')
vim.keymap.set('n', 'C', '"_C')
vim.keymap.set('n', 'cc', '"_cc')
vim.keymap.set('n', 'd', '"_d', { desc = 'Delete with motion without replacing yank register' })
vim.keymap.set('n', 'D', '"_D', { desc = 'Delete to end of line without replacing yank register' })
vim.keymap.set('n', 'dd', '"_dd', { desc = 'Delete line without replacing yank register' })
vim.keymap.set('x', 'c', '"_c')
vim.keymap.set('x', 'p', 'p:let @+=@0<CR>:let @"=@0<CR>', { desc = 'Paste without replacing yank register' })

vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight yanked text and update the yank ring',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.hl.on_yank { higroup = 'IncSearch', timeout = 300 }
    if vim.v.event.operator == 'y' then
      for index = 9, 1, -1 do
        vim.fn.setreg(tostring(index), vim.fn.getreg(tostring(index - 1)))
      end
    end
  end,
})

vim.api.nvim_create_autocmd('FileType', {
  desc = 'Enable spell checking for prose',
  group = vim.api.nvim_create_augroup('nvim2-prose-spell', { clear = true }),
  pattern = { 'gitcommit', 'markdown', 'text' },
  callback = function()
    vim.opt_local.spell = true
    vim.opt_local.spelllang = { 'en_us', 'en_gb' }
  end,
})

vim.api.nvim_create_autocmd('FileType', {
  desc = 'Allow removing individual quickfix entries',
  group = vim.api.nvim_create_augroup('nvim2-quickfix', { clear = true }),
  pattern = 'qf',
  callback = function(event)
    local wininfo = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
    if not wininfo or wininfo.loclist == 1 then return end

    vim.keymap.set('n', 'dd', function()
      local row = vim.api.nvim_win_get_cursor(0)[1]
      local qf = vim.fn.getqflist { all = 0 }
      if not qf.items[row] then return end

      table.remove(qf.items, row)
      local replacement = {
        id = qf.id,
        title = qf.title,
        context = qf.context,
        items = qf.items,
        quickfixtextfunc = qf.quickfixtextfunc,
      }
      if #qf.items > 0 then replacement.idx = math.min(row, #qf.items) end

      vim.fn.setqflist({}, 'r', replacement)
      if #qf.items > 0 then vim.api.nvim_win_set_cursor(0, { math.min(row, #qf.items), 0 }) end
    end, { buffer = event.buf, desc = 'Delete quickfix entry' })
  end,
})

vim.api.nvim_create_autocmd('BufReadPost', {
  desc = 'Restore the cursor to the last edit position',
  group = vim.api.nvim_create_augroup('nvim2-restore-cursor', { clear = true }),
  callback = function(event)
    local mark = vim.api.nvim_buf_get_mark(event.buf, '"')
    local line_count = vim.api.nvim_buf_line_count(event.buf)
    if mark[1] > 0 and mark[1] <= line_count then pcall(vim.api.nvim_win_set_cursor, 0, mark) end
  end,
})

vim.api.nvim_create_autocmd('VimResized', {
  desc = 'Resize splits when the terminal changes size',
  group = vim.api.nvim_create_augroup('nvim2-resize-splits', { clear = true }),
  command = 'wincmd =',
})
