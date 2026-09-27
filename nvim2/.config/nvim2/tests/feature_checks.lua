local function command(args, opts)
  opts = opts or {}
  opts.text = true
  local result = vim.system(args, opts):wait(10000)
  assert(result.code == 0, ('command failed (%s): %s'):format(table.concat(args, ' '), result.stderr or result.stdout or ''))
  return vim.trim(result.stdout or '')
end

local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  if type(lines) == 'string' then lines = vim.split(lines, '\n', { plain = true }) end
  assert(vim.fn.writefile(lines, path) == 0)
end

local function make_repository(path)
  vim.fn.mkdir(path, 'p')
  command { 'git', 'init', '-q', path }
  command { 'git', '-C', path, 'config', 'user.name', 'Nvim2 test' }
  command { 'git', '-C', path, 'config', 'user.email', 'nvim2-test@example.invalid' }
  write(vim.fs.joinpath(path, 'tracked.lua'), { 'local one = true', 'local two = true', 'return one and two' })
  command { 'git', '-C', path, 'add', '.' }
  command { 'git', '-C', path, 'commit', '-qm', 'fixture' }
end

local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, 'p')
local repository_a = vim.fs.joinpath(temporary, 'repository-a')
local repository_b = vim.fs.joinpath(temporary, 'repository-b')
make_repository(repository_a)
make_repository(repository_b)
local nested = vim.fs.joinpath(repository_b, 'nested')
make_repository(nested)
local worktree = vim.fs.joinpath(temporary, 'worktree')
command { 'git', '-C', repository_a, 'worktree', 'add', '-qb', 'nvim2-worktree', worktree }
local alias = vim.fs.joinpath(temporary, 'repository-b-alias')
assert(vim.uv.fs_symlink(repository_b, alias, { dir = true }))

local project = require 'custom.project'
assert(project.git_root(vim.fs.joinpath(repository_b, 'tracked.lua')) == project.canonical(repository_b))
assert(project.git_root(vim.fs.joinpath(nested, 'tracked.lua')) == project.canonical(nested), 'nearest nested Git root was not selected')
assert(project.git_root(vim.fs.joinpath(worktree, 'tracked.lua')) == project.canonical(worktree), 'Git worktree marker file was not recognized')
assert(project.git_root(vim.fs.joinpath(alias, 'new', 'future.lua')) == project.canonical(repository_b), 'symlinked new file created another root')
assert(project.git_root(vim.fs.joinpath(temporary, 'outside.lua')) == nil, 'outside-Git path gained a root')

vim.cmd.edit(vim.fs.joinpath(repository_b, 'tracked.lua'))
vim.cmd.lcd(repository_a)
assert(require('custom.telescope').nearest_git_root() == project.canonical(repository_b), 'buffer Git root did not override local cwd')
local search_options = require('custom.telescope').file_options { cwd = require('custom.telescope').nearest_git_root() }
local search = vim.system(search_options.find_command, { cwd = require('custom.telescope').nearest_git_root(), text = true }):wait(10000)
assert(search.code == 0 and search.stdout:find('tracked.lua', 1, true), 'buffer-root file picker command did not search repository B')
vim.cmd.enew()
vim.cmd.lcd(repository_a)
assert(require('custom.telescope').nearest_git_root() == vim.fn.getcwd(), 'outside-file search ignored effective local cwd')
vim.bo.buftype = 'nofile'
assert(project.buffer_git_root(0) == nil, 'special buffer gained a project root')

local function tabout_case(lines, cursor, direction, expected)
  vim.cmd.enew { bang = true }
  vim.bo.filetype = 'lua'
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.treesitter.start(0, 'lua')
  vim.treesitter.get_parser(0, 'lua'):parse(true)
  vim.api.nvim_win_set_cursor(0, cursor)
  vim.fn.setreg('"', 'preserved register', 'v')
  local before_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local before_tick = vim.b.changedtick
  local before_undo = vim.fn.undotree().seq_cur
  assert(require('custom.tabout').jump(direction), 'tab-out did not find a supported pair')
  local actual = vim.api.nvim_win_get_cursor(0)
  assert(vim.deep_equal(actual, expected), ('tab-out moved to %s, expected %s'):format(vim.inspect(actual), vim.inspect(expected)))
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), before_lines), 'tab-out changed text')
  assert(vim.b.changedtick == before_tick and vim.fn.undotree().seq_cur == before_undo, 'tab-out changed undo history')
  assert(vim.fn.getreg '"' == 'preserved register', 'tab-out changed the unnamed register')
end

tabout_case({ 'local value = outer({ inner = true })' }, { 1, 28 }, 1, { 1, 36 })
tabout_case({ 'local value = outer({ inner = true })' }, { 1, 28 }, -1, { 1, 20 })
tabout_case({ 'local value = {', '  text = "Ωmega",', '}' }, { 2, 12 }, 1, { 2, 17 })
tabout_case({ 'local value = {', '  text = "Ωmega",', '}' }, { 2, 12 }, -1, { 2, 9 })
tabout_case({ 'local value = {', '', '}' }, { 2, 0 }, 1, { 3, 0 })
tabout_case({ 'local value = "escaped \\" quote"' }, { 1, 25 }, 1, { 1, 31 })
vim.cmd.enew { bang = true }
vim.bo.filetype = 'text'
vim.api.nvim_buf_set_lines(0, 0, -1, false, { '(plain text)' })
assert(not require('custom.tabout').forward(), 'tab-out guessed without a parser')
vim.bo.buftype = 'nofile'
assert(not require('custom.tabout').forward(), 'tab-out ran in a special buffer')
vim.cmd.enew { bang = true }
vim.bo.filetype = 'lua'
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'local value = [[raw string]]' })
vim.treesitter.start(0, 'lua')
vim.treesitter.get_parser(0, 'lua'):parse(true)
vim.api.nvim_win_set_cursor(0, { 1, 18 })
assert(not require('custom.tabout').forward(), 'tab-out treated a Lua long string as a single-character bracket pair')
vim.cmd.enew { bang = true }
vim.bo.filetype = 'markdown'
vim.api.nvim_buf_set_lines(0, 0, -1, false, { '```lua', 'print(true)', '```' })
vim.treesitter.start(0, 'markdown')
vim.treesitter.get_parser(0, 'markdown'):parse(true)
vim.api.nvim_win_set_cursor(0, { 2, 3 })
assert(not require('custom.tabout').forward(), 'tab-out treated a Markdown fence as a backtick pair')

local search_lens = require 'custom.plugins.search_lens'
vim.cmd.enew { bang = true }
vim.bo.buftype = ''
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'needle first', 'middle needle', 'needle last' })
vim.fn.setreg('/', 'needle')
vim.o.hlsearch = true
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd.normal { args = { 'n' }, bang = true }
local search_register = vim.fn.getreg '/'
local search_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
search_lens.refresh()
assert(search_lens.status().active and search_lens.status().text:match '%d/3', 'search lens did not show the native count')
vim.cmd.normal { args = { 'N' }, bang = true }
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 1, 0 }), 'backward native search did not reach the previous match')
vim.cmd.normal { args = { '2n' }, bang = true }
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 3, 0 }), 'counted native search did not retain its count')
local jump_list = vim.deepcopy(vim.fn.getjumplist())
search_lens.refresh()
assert(vim.deep_equal(vim.fn.getjumplist(), jump_list), 'search-lens rendering changed the jump list')
local first_window = vim.api.nvim_get_current_win()
vim.cmd.vsplit()
search_lens.refresh()
assert(
  search_lens.status().win == vim.api.nvim_get_current_win() and search_lens.status().win ~= first_window,
  'search lens was not scoped to the active split'
)
assert(
  vim.fn.getreg '/' == search_register and vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), search_lines),
  'search lens changed search state or text'
)
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'xt', false)
assert(vim.wait(1000, function() return not search_lens.status().active end), 'normal-mode Escape left the search lens active')
vim.o.hlsearch = true
search_lens.refresh()
assert(search_lens.status().active, 'search lens did not return after search highlighting was restored')
vim.cmd.nohlsearch()
vim.api.nvim_exec_autocmds('CmdlineLeave', { pattern = ':' })
assert(vim.wait(1000, function() return not search_lens.status().active end), 'direct nohlsearch left lens state active')
search_lens.toggle()
assert(not search_lens.is_enabled() and not search_lens.status().active, 'search lens did not disable')
search_lens.toggle()
assert(search_lens.is_enabled(), 'search lens did not re-enable')
vim.cmd.only()
vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.fn['repeat']({ 'needle' }, 1001))
vim.fn.setreg('/', '\\Vneedle')
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.o.hlsearch = true
search_lens.refresh()
assert(search_lens.status().text == ' 1/>999 ', 'search lens presented a max-count result as exact: ' .. vim.inspect(search_lens.status()))
vim.fn.setreg('/', '[')
search_lens.refresh()
assert(not search_lens.status().active, 'invalid search pattern left a stale lens')

local marks = require 'custom.plugins.project_marks'
local notify = vim.notify
local mark_notifications = {}
vim.notify = function(message, level) mark_notifications[#mark_notifications + 1] = { message = message, level = level } end
local file_a = vim.fs.joinpath(repository_a, 'tracked.lua')
local file_b = vim.fs.joinpath(repository_b, 'tracked.lua')
vim.cmd.edit(file_a)
vim.api.nvim_win_set_cursor(0, { 2, 3 })
vim.cmd.normal { args = { 'ma' }, bang = true }
vim.cmd.normal { args = { 'mA' }, bang = true }
local native_local = vim.fn.getpos "'a"
local native_global = vim.fn.getpos "'A"
assert(marks.set 'shared name')
assert(marks.set 'second mark')
vim.cmd.edit(file_b)
vim.api.nvim_win_set_cursor(0, { 3, 2 })
assert(marks.set 'shared name')
assert(#marks.list(project.canonical(repository_a)) == 2 and #marks.list(project.canonical(repository_b)) == 1, 'same-name marks were not isolated by root')
assert(vim.deep_equal(vim.fn.getpos "'A", native_global), 'project marks changed the native global mark')
vim.cmd.edit(file_a)
assert(vim.deep_equal(vim.fn.getpos "'a", native_local), 'project marks changed the native local mark')

vim.cmd.edit(vim.fs.joinpath(alias, 'tracked.lua'))
assert(marks.set 'alias')
assert(#marks.list(project.canonical(repository_b)) == 2, 'symlink alias used another mark namespace')
vim.cmd.edit(file_b)
vim.api.nvim_win_set_cursor(0, { 2, 1 })
assert(marks.set 'moves')
vim.api.nvim_buf_set_lines(0, 0, 0, false, { 'local inserted = true' })
vim.api.nvim_exec_autocmds('TextChanged', { buffer = 0 })
vim.cmd.write()
local moved = vim.iter(marks.list(project.canonical(repository_b))):find(function(record) return record.name == 'moves' end)
assert(moved and moved.line == 3, 'saved edit did not persist the moved extmark')

vim.api.nvim_win_set_cursor(0, { 2, 0 })
assert(marks.set 'discarded')
vim.api.nvim_buf_set_lines(0, 0, 0, false, { 'discard this' })
vim.api.nvim_exec_autocmds('TextChanged', { buffer = 0 })
vim.cmd.edit { bang = true }
local discarded = vim.iter(marks.list(project.canonical(repository_b))):find(function(record) return record.name == 'discarded' end)
assert(discarded and discarded.line == 2, 'discarded edits were persisted')

local child_config = vim.fs.joinpath(temporary, 'child-config', 'nvim2')
write(
  vim.fs.joinpath(child_config, 'init.lua'),
  ([[
vim.opt.runtimepath:prepend(%q)
vim.opt.swapfile = false
vim.cmd.edit(%q)
assert(require('custom.plugins.project_marks').set(vim.env.NVIM2_MARK_NAME, { position = { 1, 0 } }))
]]):format(vim.fn.stdpath 'config', file_b)
)
local child_init_path = vim.fs.joinpath(child_config, 'init.lua')
local child_chunk, child_parse_error = loadfile(child_init_path)
assert(child_chunk, (child_parse_error or 'invalid child init') .. ': ' .. vim.inspect(vim.fn.readfile(child_init_path)))
local child_environment = vim.tbl_extend('force', vim.fn.environ(), {
  XDG_CONFIG_HOME = vim.fs.dirname(child_config),
  NVIM_APPNAME = 'nvim2',
})
local first_child_environment = vim.tbl_extend('force', child_environment, { NVIM2_MARK_NAME = 'process one' })
local second_child_environment = vim.tbl_extend('force', child_environment, { NVIM2_MARK_NAME = 'process two' })
local first_child = vim.system({ vim.v.progpath, '--headless', '+qa!' }, { env = first_child_environment, text = true })
local second_child = vim.system({ vim.v.progpath, '--headless', '+qa!' }, { env = second_child_environment, text = true })
local first_result = first_child:wait(30000)
local second_result = second_child:wait(30000)
assert(
  first_result.code == 0
    and second_result.code == 0
    and not first_result.stderr:find('Error in', 1, true)
    and not second_result.stderr:find('Error in', 1, true),
  ('independent Neovim processes could not persist marks:\n%s\n%s'):format(first_result.stderr, second_result.stderr)
)
local process_records = marks.list(project.canonical(repository_b))
assert(vim.iter(process_records):any(function(record) return record.name == 'process one' end), 'first process mark was lost: ' .. vim.inspect(process_records))
assert(
  vim.iter(process_records):any(function(record) return record.name == 'process two' end),
  'second process mark was lost: ' .. vim.inspect(process_records)
)

local root_b = project.canonical(repository_b)
local state_directory = vim.fs.joinpath(vim.fn.stdpath 'state', 'project-marks', vim.fn.sha256(root_b))
write(vim.fs.joinpath(state_directory, 'deadbeef.json'), '{broken')
write(
  vim.fs.joinpath(state_directory, 'cafebabe.json'),
  vim.json.encode { schema = 1, name = 'escape', root = root_b, file = '../outside.lua', line = 1, column = 0 }
)
local records_after_corruption = marks.list(root_b)
assert(#records_after_corruption == #process_records, 'invalid records erased or replaced valid project marks')
assert(
  vim.iter(mark_notifications):any(function(item) return item.message:find('invalid JSON', 1, true) end)
    and vim.iter(mark_notifications):any(function(item) return item.message:find('unsafe relative file path', 1, true) end),
  'corrupt project-mark records did not produce actionable warnings'
)
vim.uv.fs_unlink(vim.fs.joinpath(state_directory, 'deadbeef.json'))
vim.uv.fs_unlink(vim.fs.joinpath(state_directory, 'cafebabe.json'))

vim.cmd.edit(file_a)
local preserved_buffer = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(preserved_buffer, 0, 1, false, { 'local unsaved = true' })
local shared_b = vim.iter(marks.list(root_b)):find(function(record) return record.name == 'shared name' end)
assert(shared_b and marks.jump(shared_b), 'project mark could not open its recorded target')
assert(
  vim.bo[preserved_buffer].modified and vim.api.nvim_buf_get_lines(preserved_buffer, 0, 1, false)[1] == 'local unsaved = true',
  'jump discarded an unsaved buffer'
)
vim.cmd.normal { args = { vim.api.nvim_replace_termcodes('<C-o>', true, false, true) }, bang = true }
assert(vim.api.nvim_get_current_buf() == preserved_buffer, 'project-mark jump did not update normal jump history')
vim.bo[preserved_buffer].modified = false

local spaced_file = vim.fs.joinpath(repository_b, 'path with spaces.lua')
write(spaced_file, { 'local first = true', 'local second = true' })
vim.cmd.edit(spaced_file)
vim.api.nvim_win_set_cursor(0, { 2, 6 })
assert(marks.set 'spaced target')
vim.cmd.edit(file_a)
local spaced_record = vim.iter(marks.list(root_b)):find(function(record) return record.name == 'spaced target' end)
assert(spaced_record and marks.jump(spaced_record), 'structured project-mark jump failed for a path containing spaces')
assert(project.canonical(vim.api.nvim_buf_get_name(0)) == project.canonical(spaced_file), 'project-mark jump opened the wrong spaced path')

vim.cmd.edit(file_b)
vim.api.nvim_win_set_cursor(0, { 3, 0 })
assert(marks.set 'shortened target')
vim.cmd.bwipeout { bang = true }
write(file_b, 'only one line')
local shortened = vim.iter(marks.list(root_b)):find(function(record) return record.name == 'shortened target' end)
assert(shortened and marks.jump(shortened), 'shortened project-mark target did not open')
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 1, 0 }), 'shortened project-mark target was not clamped safely')

local deleted_file = vim.fs.joinpath(repository_b, 'deleted target.lua')
write(deleted_file, 'return true')
vim.cmd.edit(deleted_file)
assert(marks.set 'stale target')
local stale = vim.iter(marks.list(root_b)):find(function(record) return record.name == 'stale target' end)
vim.cmd.bwipeout { bang = true }
vim.uv.fs_unlink(deleted_file)
assert(stale and not marks.jump(stale), 'missing project-mark target was silently recreated')
assert(
  vim.iter(marks.list(root_b)):any(function(record) return record.name == 'stale target' end),
  'stale project mark was removed instead of remaining deletable'
)

vim.cmd.edit(file_b)
assert(marks.set 'external deletion')
local external_path = vim.fs.joinpath(state_directory, vim.fn.sha256 'external deletion' .. '.json')
assert(vim.uv.fs_unlink(external_path), 'could not remove project-mark record for external-deletion test')
vim.api.nvim_buf_set_lines(0, 0, 0, false, { 'local later = true' })
vim.api.nvim_exec_autocmds('TextChanged', { buffer = 0 })
vim.cmd.write()
assert(not vim.uv.fs_stat(external_path), 'a stale editor recreated a project mark deleted externally')

local failure_repository = vim.fs.joinpath(temporary, 'failure-repository')
make_repository(failure_repository)
local failure_root = project.canonical(failure_repository)
local failure_directory = vim.fs.joinpath(vim.fn.stdpath 'state', 'project-marks', vim.fn.sha256(failure_root))
assert(vim.uv.fs_symlink('/proc/1', failure_directory, { dir = true }), 'could not create the failed-write fixture')
vim.cmd.edit(vim.fs.joinpath(failure_repository, 'tracked.lua'))
local failed_write = marks.set 'must fail'
assert(vim.uv.fs_unlink(failure_directory), 'could not remove the failed-write fixture')
assert(not failed_write, 'failed project-mark write was reported as successful')
assert(not marks.set 'bad\nname', 'control characters were accepted in a project-mark name')
vim.cmd.edit(file_b)

local selected = 0
local deleted_by_mapping
local original_select = vim.ui.select
vim.ui.select = function(items, _, callback)
  selected = selected + 1
  if selected == 3 then
    deleted_by_mapping = items[1].name
    callback(items[1])
  else
    callback(nil)
  end
end
vim.fn.maparg('<leader>mm', 'n', false, true).callback()
vim.fn.maparg('<leader>sM', 'n', false, true).callback()
vim.fn.maparg('<leader>md', 'n', false, true).callback()
vim.ui.select = original_select
assert(selected == 3, 'project-mark picker mappings did not open their UI')
assert(
  deleted_by_mapping and not vim.iter(marks.list(root_b)):any(function(record) return record.name == deleted_by_mapping end),
  'project-mark delete mapping did not remove the selected record'
)
local prompted
local original_input = vim.ui.input
vim.ui.input = function(options, callback)
  prompted = options.prompt
  callback 'mapping added'
end
vim.fn.maparg('<leader>ma', 'n', false, true).callback()
vim.ui.input = original_input
assert(prompted == 'Project mark name: ', 'project-mark add mapping did not prompt')
assert(vim.iter(marks.list(root_b)):any(function(record) return record.name == 'mapping added' end), 'project-mark add mapping did not save the named position')
assert(type(vim.fn.maparg('<leader>pm', 'n', false, true).callback) == 'function', 'Mermaid preview mapping did not move to <leader>pm')

for _, root in ipairs { repository_a, repository_b } do
  for _, record in ipairs(marks.list(project.canonical(root))) do
    assert(marks.delete(record.name, project.canonical(root)))
  end
end
vim.notify = notify

local jump_map = vim.fn.maparg('<leader>j', 'n', false, true)
assert(type(jump_map.callback) == 'function', 'Mini Jump2d mapping is unavailable')
vim.cmd.enew { bang = true }
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'start', 'one Ω target' })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.fn.feedkeys('Ω', 'n')
jump_map.callback()
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 2, 4 }), 'Mini Jump2d did not jump to a Unicode character')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'x first', 'middle', 'x second' })
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.fn.feedkeys('xb', 'n')
jump_map.callback()
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 3, 0 }), 'Mini Jump2d did not resolve repeated-character labels')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'start', 'punctuation ! target' })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.fn.feedkeys('!', 'n')
jump_map.callback()
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 2, 12 }), 'Mini Jump2d did not jump to punctuation')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'start', 'x hidden', 'fold body', 'x visible' })
vim.wo.foldmethod = 'manual'
vim.cmd '2,3fold'
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.fn.feedkeys('x', 'n')
jump_map.callback()
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 4, 0 }), 'Mini Jump2d included a character hidden in a closed fold')
vim.wo.foldmethod = 'manual'
vim.cmd 'normal! zE'
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.fn.feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n')
jump_map.callback()
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 1, 0 }), 'cancelling Mini Jump2d moved the cursor')
vim.bo.buftype = 'nofile'
local before_special = vim.api.nvim_win_get_cursor(0)
jump_map.callback()
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), before_special), 'Mini Jump2d ran in a special buffer')

vim.cmd.tabnew()
local matrix_file = vim.fs.joinpath(repository_a, 'matrix.lua')
write(matrix_file, 'local matrix = true')
vim.cmd.edit(matrix_file)
vim.cmd.vsplit()
vim.cmd.enew()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'two' })
vim.cmd.split()
vim.cmd.enew()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'three' })
vim.cmd.wincmd 'h'
vim.cmd.split()
vim.cmd.enew()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'four' })
local tab = vim.api.nvim_get_current_tabpage()
local sources = vim
  .iter(vim.api.nvim_tabpage_list_wins(tab))
  :filter(function(window) return vim.api.nvim_win_get_config(window).relative == '' and vim.bo[vim.api.nvim_win_get_buf(window)].buftype == '' end)
  :totable()
assert(#sources == 4, 'Matrix fixture did not create four editing panes')
local named_source = vim.iter(sources):find(function(window) return vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(window)) == matrix_file end)
assert(named_source, 'Matrix fixture has no named source for Neo-tree')
local snapshots = {}
for _, window in ipairs(sources) do
  local buffer = vim.api.nvim_win_get_buf(window)
  snapshots[window] = {
    buffer = buffer,
    lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false),
    modified = vim.bo[buffer].modified,
    cursor = vim.api.nvim_win_get_cursor(window),
  }
end
local matrix = require 'custom.plugins.matrix'
matrix.toggle()
assert(vim.wait(1000, function() return matrix.status().active and matrix.status().overlays == 4 end), 'Matrix did not cover all four editing panes')
local function overlay_for(source)
  return vim.iter(vim.api.nvim_tabpage_list_wins(tab)):find(function(window)
    local config = vim.api.nvim_win_get_config(window)
    return config.relative == 'win' and config.win == source and vim.bo[vim.api.nvim_win_get_buf(window)].filetype == 'nvim2-matrix'
  end)
end
for _, window in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
  if vim.api.nvim_win_get_config(window).relative ~= '' then
    local buffer = vim.api.nvim_win_get_buf(window)
    assert(
      not vim.bo[buffer].buflisted and vim.bo[buffer].buftype == 'nofile' and not vim.bo[buffer].modifiable and vim.bo[buffer].readonly,
      'Matrix overlay is writable or persistent'
    )
  end
end
local focused_source = vim.api.nvim_win_get_config(vim.api.nvim_get_current_win()).win
local resized_source = vim.iter(sources):find(function(window) return window ~= focused_source and vim.api.nvim_win_get_width(window) > 10 end)
assert(resized_source, 'Matrix resize fixture had no wide source window')
vim.api.nvim_win_set_width(resized_source, vim.api.nvim_win_get_width(resized_source) - 1)
assert(
  vim.wait(1000, function()
    local overlay = overlay_for(resized_source)
    return overlay and vim.api.nvim_win_get_config(overlay).width == vim.api.nvim_win_get_width(resized_source)
  end),
  'Matrix overlay did not follow a source-window resize'
)
local replaced_overlay = overlay_for(resized_source)
local replaced_buffer = vim.api.nvim_win_get_buf(replaced_overlay)
vim.api.nvim_buf_delete(replaced_buffer, { force = true })
assert(
  vim.wait(1000, function()
    local overlay = overlay_for(resized_source)
    return overlay and vim.api.nvim_win_get_buf(overlay) ~= replaced_buffer and matrix.status().overlays == 4
  end),
  'Matrix did not recover a disposed overlay'
)
matrix.toggle()
assert(not matrix.status().active and not matrix.status().timer, 'Matrix teardown left active resources')
for window, snapshot in pairs(snapshots) do
  assert(vim.api.nvim_win_is_valid(window), 'Matrix closed a source window')
  assert(vim.api.nvim_win_get_buf(window) == snapshot.buffer, 'Matrix replaced a source buffer')
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(snapshot.buffer, 0, -1, false), snapshot.lines), 'Matrix changed source text')
  assert(vim.bo[snapshot.buffer].modified == snapshot.modified, 'Matrix changed a source modified flag')
  assert(vim.deep_equal(vim.api.nvim_win_get_cursor(window), snapshot.cursor), 'Matrix changed a source cursor')
end

vim.api.nvim_set_current_win(sources[1])
vim.cmd.vsplit()
vim.cmd.enew()
local disposable_source = vim.api.nvim_get_current_win()
vim.api.nvim_set_current_win(sources[1])
matrix.toggle()
assert(vim.wait(1000, function() return matrix.status().overlays == 5 end), 'Matrix did not add an overlay for a new ordinary pane')
vim.api.nvim_win_close(disposable_source, true)
assert(vim.wait(1000, function() return matrix.status().active and matrix.status().overlays == 4 end), 'Matrix did not reconcile a closed source window')
matrix.toggle()

matrix.toggle()
require('telescope.builtin').buffers { previewer = false }
assert(vim.wait(2000, function() return not matrix.status().active and vim.bo.filetype == 'TelescopePrompt' end), 'opening a picker did not close Matrix')
require('telescope.actions').close(vim.api.nvim_get_current_buf())

vim.api.nvim_set_current_win(named_source)
matrix.toggle()
local tree_toggle = vim.fn.maparg('\\', 'n', false, true)
assert(type(tree_toggle.callback) == 'function', 'Neo-tree toggle is unavailable from the Matrix overlay')
tree_toggle.callback()
local function tree_window()
  return vim.iter(vim.api.nvim_tabpage_list_wins(tab)):find(function(window) return vim.bo[vim.api.nvim_win_get_buf(window)].filetype == 'neo-tree' end)
end
assert(
  vim.wait(3000, function() return matrix.status().active and tree_window() ~= nil end),
  'Matrix did not preserve a Neo-tree toggle from its source context: '
    .. vim.inspect {
      matrix = matrix.status(),
      windows = vim
        .iter(vim.api.nvim_tabpage_list_wins(tab))
        :map(function(window) return { filetype = vim.bo[vim.api.nvim_win_get_buf(window)].filetype, config = vim.api.nvim_win_get_config(window) } end)
        :totable(),
      messages = vim.fn.execute 'messages',
    }
)
local tree = tree_window()
assert(not overlay_for(tree), 'Matrix covered the Neo-tree window')
vim.cmd 'Neotree close'
assert(vim.wait(3000, function() return tree_window() == nil and matrix.status().active end), 'Matrix did not reconcile after closing Neo-tree')
matrix.toggle()

for _ = 1, 3 do
  matrix.toggle()
  assert(matrix.status().active)
  matrix.toggle()
  assert(not matrix.status().active)
end
local original_set_lines = vim.api.nvim_buf_set_lines
vim.api.nvim_buf_set_lines = function() error 'injected Matrix rendering failure' end
matrix.toggle()
assert(vim.wait(3000, function() return not matrix.status().active end), 'Matrix did not tear down after a rendering failure')
vim.api.nvim_buf_set_lines = original_set_lines
assert(not matrix.status().timer and matrix.status().overlays == 0, 'Matrix rendering failure leaked resources')
matrix.toggle()
vim.cmd.tabnew()
assert(not matrix.status().active, 'Matrix survived leaving its tab')
vim.cmd.tabclose()
vim.cmd.tabclose()

vim.fn.delete(temporary, 'rf')
io.stdout:write 'Nvim2 feature checks passed\n'
vim.cmd 'qa!'
