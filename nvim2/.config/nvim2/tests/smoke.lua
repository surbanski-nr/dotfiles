local function run()
  require('custom.checks').assert_all { tools = vim.env.NVIM2_CHECK_TOOLS ~= '0' }
  assert(require('mason.settings').current.max_concurrent_installers == 1, 'Mason installers are not serialized')
  vim.lsp.enable('markdown_oxide', false)

  vim.cmd.tabnew()
  vim.cmd.edit(vim.fs.joinpath(vim.fn.stdpath 'config', 'init.lua'))
  assert(vim.bo.filetype == 'lua', 'init.lua did not receive the Lua filetype')
  assert(vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()], 'Treesitter highlighting did not attach to init.lua')
  assert(vim.wo.foldmethod == 'expr', 'native Treesitter folds did not attach to init.lua')
  assert(vim.wo.foldexpr == 'v:lua.vim.treesitter.foldexpr()', 'unexpected fold expression')

  local lua_client = { server_capabilities = {}, config = { settings = { Lua = {} } } }
  require('custom.lsp').servers.lua_ls.on_init(lua_client)
  local lua_library = lua_client.config.settings.Lua.workspace.library
  assert(
    vim.deep_equal(lua_library, { vim.env.VIMRUNTIME, '${3rd}/luv/library', '${3rd}/busted/library' }),
    'LuaLS library expanded beyond the reviewed low-memory scope'
  )

  vim.cmd.edit(vim.fs.joinpath(vim.fn.stdpath 'config', 'tests', 'nvim2-check.html'))
  assert(
    vim.wait(5000, function()
      return vim.iter(vim.lsp.get_clients { bufnr = 0 }):any(function(client) return client.name == 'html' end)
    end),
    'HTML Language Server did not attach to an HTML buffer'
  )

  local function assert_delete_preserves_yank(keys, text, column, expected)
    vim.cmd.enew()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { text })
    vim.api.nvim_win_set_cursor(0, { 1, column })
    vim.fn.setreg('"', 'saved yank', 'v')
    vim.api.nvim_feedkeys(keys, 'xt', false)
    assert(vim.api.nvim_get_current_line() == expected, keys .. ' did not delete the expected text')
    assert(vim.fn.getreg '"' == 'saved yank', keys .. ' replaced the yank register')
  end

  assert_delete_preserves_yank('D', 'alpha beta', 6, 'alpha ')
  assert_delete_preserves_yank('dw', 'alpha beta', 0, 'beta')
  assert_delete_preserves_yank('diw', 'alpha beta', 0, ' beta')
  assert_delete_preserves_yank('dd', 'alpha beta', 0, '')

  vim.cmd.enew()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'linewise yank' })
  vim.api.nvim_feedkeys('yy', 'xt', false)
  assert(vim.fn.getreg '1' == 'linewise yank\n', 'linewise yank was not added to yank history')
  assert(vim.fn.getregtype '1' == 'V', 'yank history did not preserve linewise register type')

  vim.fn.setreg('1', 'first', 'v')
  vim.fn.setreg('2', { 'second' }, 'V')
  vim.fn.setreg('3', 'third', 'v')
  vim.cmd.enew()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'anchor' })
  local yank_target = vim.api.nvim_get_current_buf()
  require('custom.telescope').yank_history { default_text = 'second' }
  assert(vim.wait(2000, function() return vim.bo.filetype == 'TelescopePrompt' end), 'yank-history Telescope picker did not open')
  local yank_prompt = vim.api.nvim_get_current_buf()
  assert(
    vim.wait(2000, function() return type(require('telescope.actions.state').get_current_picker(yank_prompt).manager) == 'table' end),
    'yank-history Telescope results did not become ready'
  )
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'xt', false)
  assert(vim.wait(2000, function() return vim.api.nvim_get_current_buf() == yank_target end), 'yank-history Telescope picker did not close')
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { 'anchor' }), 'selecting yank history changed the buffer')
  assert(vim.fn.getreg '1' == 'second\n' and vim.fn.getregtype '1' == 'V', 'selected yank was not promoted with its register type')
  assert(vim.fn.getreg '2' == 'first' and vim.fn.getreg '3' == 'third', 'promoting a yank did not preserve history order')
  vim.api.nvim_feedkeys('p', 'xt', false)
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { 'anchor', 'second' }), 'plain p did not paste the promoted yank')
  assert(type(vim.fn.maparg('<leader>sy', 'n', false, true).callback) == 'function', 'yank-history mapping is unavailable')

  vim.cmd.enew()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'replace' })
  vim.fn.setreg('"', 'saved yank', 'v')
  vim.api.nvim_feedkeys('viwP', 'xt', false)
  assert(vim.api.nvim_get_current_line() == 'saved yank', 'visual P did not replace the selection')
  assert(vim.fn.getreg '"' == 'saved yank', 'visual P replaced the yank register')

  vim.cmd.enew()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'alpha beta' })
  vim.fn.setreg('"', 'saved yank', 'v')
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('ccreplacement<Esc>', true, false, true), 'xt', false)
  assert(vim.api.nvim_get_current_line() == 'replacement', 'cc did not replace the line')
  assert(vim.fn.getreg '"' == 'saved yank', 'cc replaced the yank register')

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
    { '*', '*', 'bold', '**bold**' },
    { '_', '_', 'italic', '_italic_' },
    { '_', '*', 'both', '**_both_**' },
    { '~', '~', 'gone', '~~gone~~' },
    { '<', '<', 'https://example.com', '<https://example.com>' },
  } do
    vim.cmd.enew()
    vim.cmd 'setfiletype markdown'
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { snippet[2] .. 'x' })
    vim.api.nvim_win_set_cursor(0, { 1, #snippet[2] })
    local trigger = vim.fn.maparg(snippet[1], 'i', false, true)
    assert(type(trigger.callback) == 'function', 'Markdown snippet trigger is unavailable: ' .. snippet[1])
    local expansion = trigger.callback()
    assert(expansion ~= snippet[1], 'Markdown snippet trigger did not recognize: ' .. snippet[2] .. snippet[1])
    local keys = 'i' .. expansion .. snippet[3] .. '<Esc>'
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'xt', false)
    local actual = vim.api.nvim_get_current_line()
    assert(actual == snippet[4] .. 'x', ('Markdown snippet %s%s expanded to %q'):format(snippet[2], snippet[1], actual))
  end

  vim.cmd.enew()
  vim.cmd 'setfiletype markdown'
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { '``x' })
  vim.api.nvim_win_set_cursor(0, { 1, 2 })
  local fence_trigger = vim.fn.maparg('`', 'i', false, true)
  local fence_expansion = fence_trigger.callback()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('i' .. fence_expansion, true, false, true), 'xt', false)
  assert(vim.snippet.active { direction = 1 }, 'native fenced-block snippet is not active after its language field')
  local tab_mapping = vim.fn.maparg('<Tab>', 'i', false, true)
  assert(type(tab_mapping.callback) == 'function', 'Blink did not install its Tab mapping')
  vim.snippet.jump(1)
  assert(vim.api.nvim_win_get_cursor(0)[1] == 2, 'the native snippet engine did not reach the fenced-block body')
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('value<Esc>', true, false, true), 'xt', false)
  local fence_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  assert(vim.deep_equal(fence_lines, { '```lang', 'value', '```x' }), 'Markdown fence did not expand: ' .. vim.inspect(fence_lines))

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
  vim.cmd.enew()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { '# No diagram here' })
  mermaid.preview { executable = '' }
  assert(optional_warning and optional_warning.message:find('fenced mermaid block', 1, true), 'Mermaid preview checked the executable before the buffer')

  vim.api.nvim_buf_set_lines(0, 0, -1, false, { '```mermaid', 'flowchart LR', 'A --> B', '```' })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  optional_warning = nil
  mermaid.preview { executable = '' }
  vim.notify = original_notify
  assert(
    optional_warning and optional_warning.level == vim.log.levels.WARN and optional_warning.message:find('mermaid-ascii was not found', 1, true),
    'missing Mermaid executable did not warn inside a Mermaid block'
  )

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

  vim.cmd.enew()
  vim.api.nvim_buf_set_name(0, '/tmp/nvim2-telescope-quickfix.lua')
  vim.bo.filetype = 'lua'
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'local needle = true', 'local ignored = false', 'return needle' })
  vim.fn.setqflist({}, 'r')
  require('telescope.builtin').current_buffer_fuzzy_find { default_text = 'needle', previewer = false }
  assert(vim.wait(2000, function() return vim.bo.filetype == 'TelescopePrompt' end), 'current-buffer Telescope picker did not open')
  local fuzzy_prompt = vim.api.nvim_get_current_buf()
  assert(
    vim.wait(2000, function() return type(require('telescope.actions.state').get_current_picker(fuzzy_prompt).manager) == 'table' end),
    'current-buffer Telescope results did not become ready'
  )
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-q>', true, false, true), 'xt', false)
  assert(vim.wait(2000, function() return #vim.fn.getqflist() == 2 end), 'Telescope Ctrl-q did not export filtered current-buffer results to quickfix')
  vim.cmd.cclose()

  local quickfix_toggle = vim.fn.maparg('<leader>tq', 'n', false, true)
  assert(type(quickfix_toggle.callback) == 'function', 'quickfix toggle callback is unavailable')
  quickfix_toggle.callback()
  assert(vim.fn.getqflist({ winid = 0 }).winid ~= 0, 'quickfix toggle did not open the window')
  assert(#vim.fn.getqflist() == 2, 'opening the quickfix window changed its items')
  quickfix_toggle.callback()
  assert(vim.fn.getqflist({ winid = 0 }).winid == 0, 'quickfix toggle did not close the window')
  assert(#vim.fn.getqflist() == 2, 'closing the quickfix window changed its items')

  local quickfix_picker = vim.fn.maparg('<leader>sq', 'n', false, true)
  local loclist_picker = vim.fn.maparg('<leader>sl', 'n', false, true)
  local jumplist_picker = vim.fn.maparg('<leader>sj', 'n', false, true)
  assert(type(quickfix_picker.callback) == 'function', 'Telescope quickfix mapping is unavailable')
  assert(type(loclist_picker.callback) == 'function', 'Telescope location-list mapping is unavailable')
  assert(type(jumplist_picker.callback) == 'function', 'Telescope jump-list mapping is unavailable')

  quickfix_picker.callback()
  assert(vim.wait(2000, function() return vim.bo.filetype == 'TelescopePrompt' end), 'Telescope quickfix picker did not open')
  local prompt_buffer = vim.api.nvim_get_current_buf()
  assert(require('telescope.actions.state').get_current_picker(prompt_buffer).previewer, 'Telescope quickfix picker has no preview')
  require('telescope.actions').close(prompt_buffer)

  local telescope = require 'custom.telescope'
  local dotfiles_root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fn.stdpath 'config')))
  local file_options = telescope.file_options { cwd = dotfiles_root }
  local files = vim.system(file_options.find_command, { cwd = dotfiles_root, text = true }):wait(10000)
  assert(files.code == 0, 'hidden-aware file command failed: ' .. (files.stderr or ''))
  assert(files.stdout:find('nvim2/.config/nvim2/init.lua', 1, true), 'file search still excludes dotfiles')
  assert(not files.stdout:find('.git/', 1, true), 'file search includes Git metadata')
  assert(not files.stdout:find('node_modules/', 1, true), 'file search includes node_modules')

  local grep_command = { 'rg', '--files' }
  vim.list_extend(grep_command, telescope.grep_args())
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
  local function assert_indent_scope(language, lines, cursor, expected_node, expected_column)
    vim.cmd.enew { bang = true }
    local buffer = vim.api.nvim_get_current_buf()
    vim.bo.buftype = 'nofile'
    vim.bo.bufhidden = 'wipe'
    vim.bo.swapfile = false
    vim.bo.filetype = language
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    vim.treesitter.start(buffer, language)
    vim.treesitter.get_parser(buffer, language):parse(true)
    vim.api.nvim_win_set_cursor(0, cursor)

    local node = require('ibl.scope').get(buffer, require('ibl.config').get_config(buffer))
    assert(
      node and node:type() == expected_node,
      ('%s active indent scope is %s, expected %s'):format(language, node and node:type() or 'missing', expected_node)
    )

    vim.bo.buftype = ''
    require('ibl').refresh(buffer)
    local scope_column
    local namespace = vim.api.nvim_get_namespaces().indent_blankline
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buffer, namespace, { cursor[1] - 1, 0 }, { cursor[1] - 1, -1 }, { details = true })) do
      local column = 0
      for _, chunk in ipairs(mark[4].virt_text or {}) do
        local highlights = type(chunk[2]) == 'table' and chunk[2] or { chunk[2] }
        if vim.tbl_contains(highlights, '@ibl.scope.char.1') then
          scope_column = column
          break
        end
        column = column + vim.fn.strdisplaywidth(chunk[1])
      end
    end
    assert(
      scope_column == expected_column,
      ('%s active indent guide is at column %s, expected %d'):format(language, scope_column or 'missing', expected_column)
    )
    vim.bo.modified = false
    vim.bo.buftype = 'nofile'
  end

  assert_indent_scope('bash', {
    'run() {',
    '  if true; then',
    '    while true; do',
    '      echo value',
    '    done',
    '  fi',
    '}',
  }, { 4, 8 }, 'while_statement', 4)
  assert_indent_scope('lua', {
    'local function run()',
    '  if true then',
    '    while true do',
    '      print("value")',
    '    end',
    '  end',
    'end',
  }, { 4, 8 }, 'while_statement', 4)
  assert_indent_scope('python', {
    'def run():',
    '    if True:',
    '        while True:',
    '            print("value")',
  }, { 4, 12 }, 'while_statement', 8)
  assert_indent_scope('typescript', {
    'function run() {',
    '  if (true) {',
    '    while (true) {',
    '      console.log("value")',
    '    }',
    '  }',
    '}',
  }, { 4, 8 }, 'statement_block', 4)
  assert_indent_scope('yaml', {
    'plugins:',
    '  watch-events:',
    '    scopes:',
    '      - all',
    '    command: bash',
  }, { 4, 8 }, 'block_node', 4)

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

  vim.cmd.enew()
  local marker_lines = vim.iter(vim.fn.range(1, 101)):map(tostring):totable()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, marker_lines)
  vim.api.nvim_win_set_cursor(0, { 51, 0 })
  local source_window = vim.api.nvim_get_current_win()
  local scroll_marker = require 'custom.plugins.scroll_marker'
  scroll_marker.update()
  local marker_window = vim.iter(vim.api.nvim_list_wins()):find(function(window)
    local config = vim.api.nvim_win_get_config(window)
    if config.relative ~= 'win' or config.win ~= source_window then return false end
    return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(window), 0, -1, false)[1] == '●'
  end)
  assert(marker_window, 'right-edge scroll marker was not shown in a source buffer')
  local marker_config = vim.api.nvim_win_get_config(marker_window)
  assert(marker_config.row == scroll_marker.screen_row(51, 101, vim.api.nvim_win_get_height(source_window)), 'scroll marker row is incorrect')
  assert(marker_config.height == 1, 'scroll marker is not a single dot')
  assert(marker_config.border == 'none', 'scroll marker unexpectedly has a border')
  assert(marker_config.col == vim.api.nvim_win_get_width(source_window) - 1, 'scroll marker is not at the right edge')
  assert(scroll_marker.screen_row(101, 101, 10) == 9, 'scroll marker does not reach the final text row')
  vim.api.nvim_win_set_cursor(source_window, { 101, 0 })
  scroll_marker.update()
  marker_config = vim.api.nvim_win_get_config(marker_window)
  assert(marker_config.row + marker_config.height <= vim.api.nvim_win_get_height(source_window), 'scroll marker overlaps the statusline at end of file')
  local statusline = vim.api.nvim_eval_statusline(vim.wo[source_window].statusline, { winid = source_window }).str
  assert(statusline:find('101/101:', 1, true), 'statusline does not show current and total lines')
  assert(statusline:find('100%', 1, true), 'statusline does not show percentage position: ' .. statusline)
  vim.bo.buftype = 'nofile'
  scroll_marker.update()
  assert(not vim.api.nvim_win_is_valid(marker_window), 'scroll marker remained visible in a non-file buffer')

  assert(vim.filetype.match { filename = '/tmp/docker-compose.yml' } == 'yaml.docker-compose', 'Docker Compose filetype detection failed')
  assert(vim.filetype.match { filename = '/tmp/playbooks/site.yml' } == 'yaml.ansible', 'Ansible filetype detection failed')

  vim.cmd.enew()
  vim.api.nvim_buf_set_name(0, '/tmp/nvim2-check/.github/workflows/invalid.yml')
  vim.bo.filetype = 'yaml'
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'name: Test', 'on: [push]', 'jobs:', '  test:', '    steps: []' })
  vim.api.nvim_exec_autocmds('BufWritePost', { buffer = 0 })
  local actionlint_namespace = require('lint').get_namespace 'actionlint'
  assert(
    vim.wait(5000, function() return #vim.diagnostic.get(0, { namespace = actionlint_namespace }) > 0 end),
    'Actionlint did not diagnose a GitHub Actions workflow'
  )
  vim.cmd.bwipeout { bang = true }

  vim.cmd.enew()
  vim.api.nvim_buf_set_name(0, '/tmp/nvim2-check/config.yml')
  vim.bo.filetype = 'yaml'
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'name: Test', 'on: [push]', 'jobs:', '  test:', '    steps: []' })
  vim.api.nvim_exec_autocmds('BufWritePost', { buffer = 0 })
  vim.wait(300)
  assert(#vim.diagnostic.get(0, { namespace = actionlint_namespace }) == 0, 'Actionlint ran outside .github/workflows')
  vim.cmd.bwipeout { bang = true }

  local eslint_root = vim.fn.tempname()
  vim.fn.mkdir(eslint_root, 'p')
  vim.fn.writefile({ "export default [{ files: ['**/*.ts'], rules: { 'no-unused-vars': 'error' } }];" }, vim.fs.joinpath(eslint_root, 'eslint.config.mjs'))
  vim.fn.writefile({ '{}' }, vim.fs.joinpath(eslint_root, 'package-lock.json'))
  vim.fn.writefile({ '{ "compilerOptions": { "strict": true } }' }, vim.fs.joinpath(eslint_root, 'tsconfig.json'))
  vim.cmd.enew()
  vim.api.nvim_buf_set_name(0, vim.fs.joinpath(eslint_root, 'sample.ts'))
  vim.bo.filetype = 'typescript'
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'const unused={answer:42};' })
  assert(
    vim.wait(5000, function()
      return vim.iter(vim.lsp.get_clients { bufnr = 0 }):any(function(client) return client.name == 'ts_ls' end)
    end),
    'TypeScript Language Server did not attach to a TypeScript project'
  )
  assert(vim.api.nvim_buf_get_commands(0, {}).LspTypescriptSourceAction, 'TypeScript source-action command is unavailable')
  require('conform').format { bufnr = 0, async = false, timeout_ms = 5000 }
  assert(vim.api.nvim_get_current_line() == 'const unused = { answer: 42 };', 'Prettier did not format TypeScript')
  vim.api.nvim_exec_autocmds('BufWritePost', { buffer = 0 })
  local eslint_namespace = require('lint').get_namespace 'eslint_d'
  assert(
    vim.wait(5000, function() return #vim.diagnostic.get(0, { namespace = eslint_namespace }) > 0 end),
    'eslint_d did not diagnose TypeScript in a configured project'
  )
  assert(vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()], 'Treesitter highlighting did not attach to TypeScript')
  vim.cmd.bwipeout { bang = true }
  vim.fn.delete(eslint_root, 'rf')

  vim.cmd.enew()
  vim.bo.filetype = 'lua'
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'local result = call(value)' })
  vim.treesitter.start(0, 'lua')
  vim.api.nvim_win_set_cursor(0, { 1, 20 })
  local selection_start = vim.fn.maparg('<C-Space>', 'n', false, true)
  local selection_expand = vim.fn.maparg('<C-Space>', 'x', false, true)
  local selection_shrink = vim.fn.maparg('<BS>', 'x', false, true)
  assert(type(selection_start.callback) == 'function', 'Treesitter selection start callback is unavailable')
  assert(type(selection_expand.callback) == 'function', 'Treesitter selection expand callback is unavailable')
  assert(type(selection_shrink.callback) == 'function', 'Treesitter selection shrink callback is unavailable')

  local function selection_range()
    local anchor = vim.fn.getpos 'v'
    local cursor = vim.fn.getpos '.'
    return { anchor[2], anchor[3], cursor[2], cursor[3] }
  end

  selection_start.callback()
  assert(vim.fn.mode() == 'v', 'Treesitter selection did not enter visual mode')
  local first_selection = selection_range()
  selection_expand.callback()
  local expanded_selection = selection_range()
  assert(not vim.deep_equal(expanded_selection, first_selection), 'Treesitter selection did not expand')
  selection_shrink.callback()
  assert(vim.deep_equal(selection_range(), first_selection), 'Treesitter selection did not shrink to the previous node')
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'xt', false)

  vim.cmd.enew()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'true' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local toggle = vim.fn.maparg('<leader>tv', 'n', false, true)
  assert(type(toggle.callback) == 'function', 'value-toggle callback is unavailable')
  toggle.callback()
  assert(vim.api.nvim_get_current_line() == 'false', 'value toggle did not change true to false')

  notify = vim.notify
  vim.notify = function() end
  assert(not vim.g.disable_autoformat, 'format-on-save unexpectedly starts disabled')
  vim.cmd.FormatToggle()
  assert(vim.g.disable_autoformat, 'FormatToggle did not disable format-on-save')
  vim.cmd.FormatToggle()
  assert(not vim.g.disable_autoformat, 'FormatToggle did not re-enable format-on-save')
  vim.notify = notify
end

local ok, error_message = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(error_message .. '\n')
  vim.cmd 'cquit 1'
else
  io.stdout:write 'Nvim2 smoke checks passed\n'
  vim.cmd 'qa!'
end
