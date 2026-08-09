local function run()
  local plugin_loader = require 'custom.plugin_loader'
  local fixture_dir = vim.fn.tempname()
  vim.fn.mkdir(fixture_dir, 'p')
  vim.fn.writefile({ 'return true' }, vim.fs.joinpath(fixture_dir, 'valid.lua'))
  vim.uv.fs_symlink('/nvim2-missing-plugin.lua', vim.fs.joinpath(fixture_dir, 'broken.lua'))
  local fixture_ok, fixture_error = xpcall(function()
    local modules, broken = plugin_loader.scan(fixture_dir)
    assert(vim.deep_equal(modules, { 'valid' }), 'plugin loader did not isolate the valid module')
    assert(#broken == 1 and vim.fs.basename(broken[1]) == 'broken.lua', 'plugin loader did not report the dangling symlink')
  end, debug.traceback)
  vim.fs.rm(fixture_dir, { recursive = true, force = true })
  assert(fixture_ok, fixture_error)

  require('custom.checks').assert_all { tools = vim.env.NVIM2_CHECK_TOOLS ~= '0' }

  vim.cmd.edit(vim.fs.joinpath(vim.fn.stdpath 'config', 'init.lua'))
  assert(vim.bo.filetype == 'lua', 'init.lua did not receive the Lua filetype')
  assert(vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()], 'Treesitter highlighting did not attach to init.lua')
  assert(vim.wo.foldmethod == 'expr', 'native Treesitter folds did not attach to init.lua')
  assert(vim.wo.foldexpr == 'v:lua.vim.treesitter.foldexpr()', 'unexpected fold expression')
  assert(#require('luasnip').get_snippets 'lua' > 0, 'custom Lua snippets were not loaded')

  assert(vim.wait(5000, function() return vim.fn.maparg('<leader>tb', 'n') ~= '' end), 'Gitsigns did not attach within five seconds')
  assert(vim.fn.maparg('<leader>hs', 'n') ~= '', 'Gitsigns hunk mapping is missing')

  vim.cmd.edit(vim.fs.joinpath(vim.fn.stdpath 'config', 'README.md'))
  assert(#require('luasnip').get_snippets 'markdown' > 0, 'custom Markdown snippets were not loaded')

  assert(vim.filetype.match { filename = '/tmp/docker-compose.yml' } == 'yaml.docker-compose', 'Docker Compose filetype detection failed')
  assert(vim.filetype.match { filename = '/tmp/playbooks/site.yml' } == 'yaml.ansible', 'Ansible filetype detection failed')

  vim.cmd.enew()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'true' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local toggle = vim.fn.maparg('<leader>tv', 'n', false, true)
  assert(type(toggle.callback) == 'function', 'value-toggle callback is unavailable')
  toggle.callback()
  assert(vim.api.nvim_get_current_line() == 'false', 'value toggle did not change true to false')

  local notify = vim.notify
  vim.notify = function() end
  local highlight_colors = vim.fn.maparg('<leader>tc', 'n', false, true)
  assert(type(highlight_colors.callback) == 'function', 'color-highlight callback is unavailable')
  highlight_colors.callback()
  assert(require('nvim-highlight-colors').is_active(), 'inline color highlighting did not start')
  highlight_colors.callback()
  assert(not require('nvim-highlight-colors').is_active(), 'inline color highlighting did not stop')

  assert(not vim.g.disable_autoformat, 'format-on-save unexpectedly starts disabled')
  vim.cmd.FormatToggle()
  assert(vim.g.disable_autoformat, 'FormatToggle did not disable format-on-save')
  vim.cmd.FormatToggle()
  assert(not vim.g.disable_autoformat, 'FormatToggle did not re-enable format-on-save')
  vim.notify = notify

  local colors_ok = pcall(vim.api.nvim_get_autocmds, { group = 'nvim2-default-colors' })
  if not colors_ok then vim.api.nvim_exec_autocmds('VimEnter', {}) end
  assert(vim.wo.cursorline, 'current-line highlighting is disabled')
  local cursor_line = vim.api.nvim_get_hl(0, { name = 'CursorLine', link = false })
  assert(cursor_line.bg == 0x343842, 'current-line background override is missing')
  local cursor_line_number = vim.api.nvim_get_hl(0, { name = 'CursorLineNr', link = false })
  assert(cursor_line_number.fg == 0xff9e64, 'current-line number is not orange')
  assert(not cursor_line_number.bold, 'current-line number is unexpectedly bold')
  local groups = { 'Normal', 'Comment', 'Function', 'String', 'CursorLine', 'CursorLineNr' }
  local original = {}
  for _, group in ipairs(groups) do
    original[group] = vim.api.nvim_get_hl(0, { name = group, link = false })
  end
  vim.cmd.colorscheme 'isekai'
  vim.cmd.colorscheme 'default'
  for _, group in ipairs(groups) do
    assert(vim.deep_equal(original[group], vim.api.nvim_get_hl(0, { name = group, link = false })), ('default colors were not restored for %s'):format(group))
  end
end

local ok, error_message = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(error_message .. '\n')
  vim.cmd 'cquit 1'
else
  io.stdout:write 'Nvim2 smoke checks passed\n'
  vim.cmd 'qa!'
end
