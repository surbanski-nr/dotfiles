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
  assert(vim.wait(5000, function() return vim.fn.maparg('<leader>tb', 'n') ~= '' end), 'Gitsigns did not attach within five seconds')
  assert(vim.fn.maparg('<leader>hs', 'n') ~= '', 'Gitsigns hunk mapping is missing')

  for _, pair in ipairs {
    { '(', ')', '(value)' },
    { '[', ']', '[value]' },
    { '{', '}', '{value}' },
    { "'", "'", "'value'" },
    { '"', '"', '"value"' },
  } do
    vim.cmd.enew()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('i' .. pair[1] .. 'value<Esc>', true, false, true), 'xt', false)
    assert(vim.api.nvim_get_current_line() == pair[3], 'automatic pair did not expand: ' .. pair[1] .. pair[2])
  end

  vim.cmd.edit(vim.fs.joinpath(vim.fn.stdpath 'config', 'README.md'))
  assert(vim.fn.maparg('`', 'i') ~= '', 'Markdown fenced-block mapping is missing')

  for _, snippet in ipairs {
    { '**bold', '**bold**' },
    { '__italic', '_italic_' },
    { '*_both', '**_both_**' },
    { '~~gone', '~~gone~~' },
    { '<<https://example.com', '<https://example.com>' },
  } do
    vim.cmd.enew()
    vim.cmd 'setfiletype markdown'
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('i' .. snippet[1] .. '<Esc>', true, false, true), 'xt', false)
    assert(vim.api.nvim_get_current_line() == snippet[2], 'Markdown snippet did not expand: ' .. snippet[1])
  end

  vim.cmd.enew()
  vim.cmd 'setfiletype markdown'
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('i```', true, false, true), 'xt', false)
  vim.api.nvim_feedkeys('lua', 'xt', false)
  assert(vim.snippet.active { direction = 1 }, 'native fenced-block snippet is not active after its language field')
  local tab_mapping = vim.fn.maparg('<Tab>', 'i', false, true)
  assert(type(tab_mapping.callback) == 'function', 'Blink did not install its Tab mapping')
  vim.snippet.jump(1)
  assert(vim.api.nvim_win_get_cursor(0)[1] == 2, 'the native snippet engine did not reach the fenced-block body')
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('ivalue<Esc>', true, false, true), 'xt', false)
  local fence_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  assert(vim.deep_equal(fence_lines, { '```lua', 'value', '```' }), 'Markdown fence did not expand: ' .. vim.inspect(fence_lines))

  local mermaid = require 'custom.plugins.mermaid_ascii'
  local block = mermaid.find_block({
    '# Diagram',
    '',
    '```mermaid',
    'flowchart LR',
    '    A --> B',
    '```',
  }, 5)
  assert(block and block.start_line == 3 and block.end_line == 6, 'Mermaid fence was not detected')
  assert(block.source == 'flowchart LR\n    A --> B', 'Mermaid source was not extracted exactly')
  assert(mermaid.find_block({ '```lua', 'print(true)', '```' }, 2) == nil, 'non-Mermaid fence was accepted')

  local original_notify = vim.notify
  local optional_warning
  vim.notify = function(message, level) optional_warning = { message = message, level = level } end
  mermaid.preview { executable = '' }
  vim.notify = original_notify
  assert(optional_warning and optional_warning.level == vim.log.levels.WARN, 'missing Mermaid executable did not warn')

  local renderer = vim.fn.tempname()
  vim.fn.writefile({ '#!/bin/sh', 'cat >/dev/null', "printf 'A --> B\\n'" }, renderer)
  vim.uv.fs_chmod(renderer, 493)
  vim.cmd.enew()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { '```mermaid', 'flowchart LR', 'A --> B', '```' })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  local source_tab = vim.api.nvim_get_current_tabpage()
  mermaid.preview { executable = renderer }
  assert(vim.wait(5000, function() return vim.api.nvim_get_current_tabpage() ~= source_tab end), 'Mermaid preview did not open')
  assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == 'A --> B', 'Mermaid preview output is incorrect')
  assert(not vim.wo.wrap and vim.bo.buftype == 'nofile', 'Mermaid preview buffer options are incorrect')
  assert(vim.fn.maparg('q', 'n') ~= '', 'Mermaid preview close mapping is missing')
  vim.cmd.tabclose()
  vim.uv.fs_unlink(renderer)

  local telescope_search = require 'custom.plugins.telescope_search'
  local dotfiles_root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fn.stdpath 'config')))
  local file_options = telescope_search.file_options { cwd = dotfiles_root }
  local files = vim.system(file_options.find_command, { cwd = dotfiles_root, text = true }):wait(10000)
  assert(files.code == 0, 'hidden-aware file command failed: ' .. (files.stderr or ''))
  assert(files.stdout:find('nvim2/.config/nvim2/init.lua', 1, true), 'file search still excludes dotfiles')
  assert(not files.stdout:find('.git/', 1, true), 'file search includes Git metadata')
  assert(not files.stdout:find('node_modules/', 1, true), 'file search includes node_modules')

  local grep_command = { 'rg', '--files' }
  vim.list_extend(grep_command, telescope_search.grep_args())
  local grep_files = vim.system(grep_command, { cwd = dotfiles_root, text = true }):wait(10000)
  assert(grep_files.code == 0, 'hidden-aware grep command failed: ' .. (grep_files.stderr or ''))
  assert(grep_files.stdout:find('bash/.bashrc', 1, true), 'live-grep arguments still exclude dotfiles')
  assert(not grep_files.stdout:find('.git/', 1, true), 'live-grep arguments include Git metadata')
  assert(not grep_files.stdout:find('node_modules/', 1, true), 'live-grep arguments include node_modules')
  local telescope_pickers = require('telescope.config').pickers
  assert(telescope_pickers.find_files.find_command, 'Telescope find_files default was not overridden')
  assert(telescope_pickers.live_grep.additional_args, 'Telescope live_grep default was not overridden')

  local indent_config = require('ibl.config').get_config(-1)
  assert(indent_config.indent.char == '▏', 'indent guide is not using the narrow solid character')
  assert(vim.fn.strdisplaywidth(indent_config.indent.char) == 1, 'indent guide character is wider than one cell')
  assert(indent_config.scope.enabled, 'current-scope indent guide is disabled')
  assert(indent_config.scope.char == '▏', 'current-scope guide does not match the normal guide width')
  assert(vim.fn.strdisplaywidth(indent_config.scope.char) == 1, 'current-scope guide character is wider than one cell')
  assert(not indent_config.scope.show_start and not indent_config.scope.show_end, 'current scope draws unwanted boundary underlines')
  local indent_highlight = vim.api.nvim_get_hl(0, { name = 'Nvim2IndentGuide', link = false })
  assert(indent_highlight.fg == 0x4f5358, 'indent guide does not use the visible NonText grey')
  local scope_highlight = vim.api.nvim_get_hl(0, { name = 'Nvim2IndentScope', link = false })
  assert(scope_highlight.fg == 0xe0e2ea, 'current-scope guide does not use the default white foreground')
  vim.cmd.enew()
  vim.bo.filetype = 'lua'
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'local expected = {', '  {', '    value = true,', '  },', '}' })
  vim.api.nvim_win_set_cursor(0, { 3, 4 })
  vim.cmd.redraw()
  assert(
    vim.wait(2000, function()
      local namespace = vim.api.nvim_get_namespaces().indent_blankline
      if not namespace then return false end
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, { details = true })) do
        for _, chunk in ipairs(mark[4].virt_text or {}) do
          local highlights = type(chunk[2]) == 'table' and chunk[2] or { chunk[2] }
          if chunk[1] == '▏' and vim.tbl_contains(highlights, '@ibl.scope.char.1') then return true end
        end
      end
      return false
    end),
    'current Lua table scope guide was not rendered'
  )
  local enclosing_pairs = require 'custom.plugins.enclosing_pairs'
  local nested_pair = enclosing_pairs.find(0, { 2, 4 })
  assert(nested_pair, 'enclosing bracket pair was not found from inside a Lua table')
  assert(nested_pair.open == '{' and nested_pair.close == '}', 'unexpected enclosing bracket pair')
  assert(nested_pair.start[1] == 1 and nested_pair.finish[1] == 3, 'the nearest Lua table pair was not selected')
  enclosing_pairs.update()
  local enclosing_match = vim.iter(vim.fn.getmatches()):find(
    function(match) return match.group == 'MatchParen' and match.pos1 and match.pos1[1] == 2 and match.pos2 and match.pos2[1] == 4 end
  )
  assert(enclosing_match, 'enclosing Lua table brackets were not highlighted away from the delimiters')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'local value = {', '', '}' })
  vim.treesitter.get_parser(0, 'lua'):parse()
  local blank_line_pair = enclosing_pairs.find(0, { 1, 0 })
  assert(blank_line_pair and blank_line_pair.start[1] == 0 and blank_line_pair.finish[1] == 2, 'enclosing brackets were not found from a blank line')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'local value = {}' })
  vim.api.nvim_win_set_cursor(0, { 1, 14 })
  vim.api.nvim_exec_autocmds('CursorMoved', { buffer = 0 })
  assert(vim.iter(vim.fn.getmatches()):any(function(match) return match.group == 'MatchParen' end), 'built-in matching-pair highlight was not applied')
  vim.cmd.IBLToggle()
  assert(not require('ibl.config').get_config(-1).enabled, 'IBLToggle did not disable indent guides')
  vim.cmd.IBLToggle()
  assert(require('ibl.config').get_config(-1).enabled, 'IBLToggle did not re-enable indent guides')

  vim.wo.number = true
  vim.wo.relativenumber = true
  local notify = vim.notify
  vim.notify = function() end
  local line_numbers = vim.fn.maparg('<leader>tl', 'n', false, true)
  assert(type(line_numbers.callback) == 'function', 'line-number toggle callback is unavailable')
  line_numbers.callback()
  assert(vim.wo.number and not vim.wo.relativenumber, 'line numbers did not switch to absolute mode')
  line_numbers.callback()
  assert(vim.wo.number and vim.wo.relativenumber, 'line numbers did not switch back to relative mode')
  vim.notify = notify

  assert(vim.filetype.match { filename = '/tmp/docker-compose.yml' } == 'yaml.docker-compose', 'Docker Compose filetype detection failed')
  assert(vim.filetype.match { filename = '/tmp/playbooks/site.yml' } == 'yaml.ansible', 'Ansible filetype detection failed')

  vim.cmd.enew()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'true' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local toggle = vim.fn.maparg('<leader>tv', 'n', false, true)
  assert(type(toggle.callback) == 'function', 'value-toggle callback is unavailable')
  toggle.callback()
  assert(vim.api.nvim_get_current_line() == 'false', 'value toggle did not change true to false')

  notify = vim.notify
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
  local matching_pair = vim.api.nvim_get_hl(0, { name = 'MatchParen', link = false })
  assert(matching_pair.fg == 0xff9e64 and matching_pair.bg == 0x3f342d, 'matching brackets do not use the orange highlight')
  assert(not matching_pair.bold, 'matching brackets are unexpectedly bold')
  local groups = { 'Normal', 'Comment', 'Function', 'String', 'CursorLine', 'CursorLineNr', 'MatchParen' }
  local original = {}
  for _, group in ipairs(groups) do
    original[group] = vim.api.nvim_get_hl(0, { name = group, link = false })
  end
  vim.cmd.colorscheme 'surb'
  local local_function = vim.api.nvim_get_hl(0, { name = 'Function', link = false })
  assert(local_function.fg == 0x6fb8d9 and not local_function.bold, 'local function highlight is incorrect')
  vim.cmd.colorscheme 'default'
  for _, group in ipairs(groups) do
    assert(vim.deep_equal(original[group], vim.api.nvim_get_hl(0, { name = group, link = false })), ('default colors were not restored for %s'):format(group))
  end
  assert(vim.api.nvim_get_hl(0, { name = 'Nvim2IndentGuide', link = false }).fg == 0x4f5358, 'indent guide color was not restored after colorscheme changes')
  assert(
    vim.api.nvim_get_hl(0, { name = 'Nvim2IndentScope', link = false }).fg == 0xe0e2ea,
    'current-scope guide color was not restored after colorscheme changes'
  )
end

local ok, error_message = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(error_message .. '\n')
  vim.cmd 'cquit 1'
else
  io.stdout:write 'Nvim2 smoke checks passed\n'
  vim.cmd 'qa!'
end
