local api = vim.api
local root = vim.fn.tempname() .. '-git-shortcuts'
local original_cwd = vim.fn.getcwd()

-- Test fixtures must not inherit host Git hooks, signing or ignore rules.
vim.env.GIT_CONFIG_GLOBAL = '/dev/null'
vim.env.GIT_CONFIG_NOSYSTEM = '1'

local function wait_for(message, predicate) assert(vim.wait(5000, predicate, 10), message) end

local function git(...)
  local args = { 'git', '-C', root }
  vim.list_extend(args, { ... })
  local result = vim.system(args, { text = true, timeout = 10000 }):wait()
  assert(result.code == 0, result.stderr or result.stdout)
  return result.stdout
end

local function feed(keys) api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true), 'xt', false) end

local function same_lines(buffer, expected, message)
  local actual = api.nvim_buf_get_lines(buffer, 0, -1, false)
  assert(vim.deep_equal(actual, expected), message .. ': ' .. vim.inspect(actual))
end

local function run()
  vim.fn.mkdir(root, 'p')
  local file = root .. '/review.txt'
  local head = { 'start', 'stage-old', 'work-old', 'removed', 'end' }
  local index = { 'start', 'stage-new', 'work-old', 'removed', 'end' }
  local disk = { 'start', 'stage-new', 'work-saved', 'end' }
  local unsaved = { 'start', 'stage-new', 'work-unsaved', 'buffer-only', 'end' }
  assert(vim.fn.writefile(head, file) == 0)
  git('init', '--quiet')
  git('add', 'review.txt')
  git('-c', 'user.name=Nvim2 test', '-c', 'user.email=nvim2-test@example.invalid', 'commit', '--quiet', '-m', 'fixture')
  assert(vim.fn.writefile(index, file) == 0)
  git('add', 'review.txt')
  assert(vim.fn.writefile(disk, file) == 0)
  vim.cmd.cd(vim.fn.fnameescape(root))

  for _, source in ipairs { 'empty', 'untracked' } do
    if source == 'empty' then
      vim.cmd.enew()
    else
      local notes = root .. '/zz-notes.txt'
      assert(vim.fn.writefile({ 'personal notes' }, notes) == 0)
      vim.cmd.edit(vim.fn.fnameescape(notes))
    end
    feed '<leader>hv'
    local panel
    wait_for('repository viewer did not open from an ' .. source .. ' buffer', function()
      local diff_windows = 0
      for _, window in ipairs(api.nvim_tabpage_list_wins(0)) do
        if vim.bo[api.nvim_win_get_buf(window)].filetype == 'gitsigns-diff' then panel = window end
        if vim.wo[window].diff then diff_windows = diff_windows + 1 end
      end
      -- The panel appears before its initial asynchronous file open finishes.
      local selection = api.nvim_get_namespaces().gitsigns_diff_selection
      return panel and diff_windows == 2 and selection and #api.nvim_buf_get_extmarks(api.nvim_win_get_buf(panel), selection, 0, -1, {}) == 1
    end)
    local files = table.concat(api.nvim_buf_get_lines(api.nvim_win_get_buf(panel), 0, -1, false), '\n')
    assert(files:find('review.txt', 1, true), 'repository viewer omitted a changed file')
    if source == 'untracked' then assert(files:find('zz-notes.txt', 1, true), 'repository viewer omitted an untracked file') end
    for _, window in ipairs(api.nvim_tabpage_list_wins(0)) do
      if vim.wo[window].diff then
        local buffer = api.nvim_win_get_buf(window)
        local revision = api.nvim_buf_get_name(buffer):find('gitsigns://', 1, true)
        same_lines(buffer, revision and head or disk, 'repository viewer displayed the wrong comparison')
      end
    end
    api.nvim_set_current_win(panel)
    feed 'q'
    wait_for('repository viewer did not close', function()
      for _, window in ipairs(api.nvim_list_wins()) do
        if vim.bo[api.nvim_win_get_buf(window)].filetype == 'gitsigns-diff' then return false end
      end
      return true
    end)
  end

  vim.cmd.edit(vim.fn.fnameescape(file))
  local buffer = api.nvim_get_current_buf()
  local window = api.nvim_get_current_win()
  local gitsigns = require 'gitsigns'
  local unified = require 'gitsigns.unified'
  wait_for('tracked buffer did not attach', function() return gitsigns.get_hunks() ~= nil end)
  api.nvim_buf_set_lines(buffer, 0, -1, false, unsaved)
  wait_for('unsaved buffer changes were not detected', function()
    for _, hunk in ipairs(gitsigns.get_hunks() or {}) do
      if vim.tbl_contains(hunk.lines, '+buffer-only') then return true end
    end
    return false
  end)

  for _, case in ipairs {
    { keys = '<leader>hu', base = index },
    { keys = '<leader>hU', base = head },
  } do
    feed(case.keys)
    wait_for(case.keys .. ' did not render a full inline diff', function()
      local view = unified.get_view(window)
      if not view or not view.hunks then return false end
      for _, mark in ipairs(api.nvim_buf_get_extmarks(buffer, view.ns, 0, -1, { details = true })) do
        if mark[4].virt_lines and #mark[4].virt_lines > 0 then return true end
      end
      return false
    end)
    same_lines(unified.get_view(window).base, case.base, case.keys .. ' selected the wrong base')
    same_lines(buffer, unsaved, 'inline diff changed the buffer text')
    assert(vim.bo[buffer].modified, 'inline diff cleared unsaved edits')
    feed(case.keys)
    wait_for(case.keys .. ' did not close the inline diff', function() return not unified.get_view(window) end)
    same_lines(buffer, unsaved, 'closing inline diff changed the buffer text')
  end

  assert(vim.deep_equal(vim.fn.readfile(file), disk), 'review changed the saved working tree')
  assert(vim.deep_equal(vim.split(git('show', ':review.txt'), '\n', { trimempty = true }), index), 'review changed staging')
end

local ok, error_message = xpcall(run, debug.traceback)
vim.cmd.cd(vim.fn.fnameescape(original_cwd))
vim.fn.delete(root, 'rf')
if not ok then
  io.stderr:write(error_message .. '\n')
  vim.cmd 'cquit 1'
else
  io.stdout:write 'Nvim2 Git shortcut checks passed\n'
  vim.cmd 'qa!'
end
