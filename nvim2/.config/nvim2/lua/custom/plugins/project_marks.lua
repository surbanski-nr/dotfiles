local M = {}

local project = require 'custom.project'
local namespace = vim.api.nvim_create_namespace 'nvim2-project-marks'
local tracked = {}

local function warn(message) vim.notify(message, vim.log.levels.WARN, { title = 'Project marks' }) end

local function valid_name(name) return type(name) == 'string' and name:match '%S' ~= nil and #name <= 100 and not name:find '[%c]' end

local function safe_relative(path)
  if type(path) ~= 'string' or path == '' or path:sub(1, 1) == '/' then return false end
  for component in path:gmatch '[^/]+' do
    if component == '..' or component == '.' or component == '' then return false end
  end
  return true
end

local function root_directory(root) return vim.fs.joinpath(vim.fn.stdpath 'state', 'project-marks', vim.fn.sha256(root)) end

local function record_path(root, name) return vim.fs.joinpath(root_directory(root), vim.fn.sha256(name) .. '.json') end

local function inside(root, path) return path == root or vim.startswith(path, root .. '/') end

local function validate_record(record, expected_root)
  if type(record) ~= 'table' or vim.islist(record) then return nil, 'record is not a JSON object' end
  if record.schema ~= 1 then return nil, ('unsupported schema version: %s'):format(tostring(record.schema)) end
  if not valid_name(record.name) then return nil, 'record has an invalid name' end
  if type(record.root) ~= 'string' or record.root:sub(1, 1) ~= '/' then return nil, 'record has an invalid repository root' end
  if expected_root and record.root ~= expected_root then return nil, 'record belongs to a different repository root' end
  if not safe_relative(record.file) then return nil, 'record has an unsafe relative file path' end
  if type(record.line) ~= 'number' or record.line % 1 ~= 0 or record.line < 1 then return nil, 'record has an invalid line' end
  if type(record.column) ~= 'number' or record.column % 1 ~= 0 or record.column < 0 then return nil, 'record has an invalid byte column' end

  local target = project.canonical(vim.fs.joinpath(record.root, record.file))
  if not target or not inside(record.root, target) then return nil, 'record target escapes its repository root' end
  return record, nil, target
end

local function decode_record(path, expected_root)
  local read_ok, lines = pcall(vim.fn.readfile, path)
  if not read_ok then return nil, ('could not read %s: %s'):format(path, lines) end
  local decode_ok, decoded = pcall(vim.json.decode, table.concat(lines, '\n'))
  if not decode_ok then return nil, ('invalid JSON in %s: %s'):format(path, decoded) end
  local record, message, target = validate_record(decoded, expected_root)
  if not record then return nil, ('invalid record %s: %s'):format(path, message) end
  return record, nil, target
end

local function ensure_directory(path)
  local create_ok, result = pcall(vim.fn.mkdir, path, 'p', 448)
  local state = vim.uv.fs_lstat(path)
  assert(state and state.type == 'directory', ('could not create state directory %s: %s'):format(path, create_ok and tostring(result) or result))
  local ok, message = vim.uv.fs_chmod(path, 448)
  assert(ok, ('could not set private permissions on %s: %s'):format(path, message))
end

local function write_record(record)
  local directory = root_directory(record.root)
  ensure_directory(vim.fs.dirname(directory))
  ensure_directory(directory)
  local destination = record_path(record.root, record.name)
  local temporary = ('%s.tmp.%d.%s'):format(destination, vim.fn.getpid(), tostring(vim.uv.hrtime()))
  local write_ok, result = pcall(vim.fn.writefile, { vim.json.encode(record) }, temporary, 'b')
  if not write_ok or result ~= 0 then
    pcall(vim.uv.fs_unlink, temporary)
    error(('could not write project mark %s: %s'):format(record.name, result), 0)
  end
  local chmod_ok, chmod_error = vim.uv.fs_chmod(temporary, 384)
  if not chmod_ok then
    pcall(vim.uv.fs_unlink, temporary)
    error(('could not set private permissions on %s: %s'):format(temporary, chmod_error), 0)
  end
  local rename_ok, rename_error = vim.uv.fs_rename(temporary, destination)
  if not rename_ok then
    pcall(vim.uv.fs_unlink, temporary)
    error(('could not replace project mark %s atomically: %s'):format(record.name, rename_error), 0)
  end
  return destination
end

local function context(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local root = project.buffer_git_root(bufnr)
  if not root then return nil, 'Current buffer is not a normal file inside a Git repository' end
  local file = project.canonical(vim.api.nvim_buf_get_name(bufnr))
  if not file or not inside(root, file) then return nil, 'Current file is outside its canonical Git root' end
  local relative = vim.fs.relpath(root, file)
  if not safe_relative(relative) then return nil, 'Could not create a safe repository-relative path for the current file' end
  return { root = root, file = relative, bufnr = bufnr }
end

local function track(record, bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  local buffer_path = project.canonical(vim.api.nvim_buf_get_name(bufnr))
  local _, _, target = validate_record(record, record.root)
  if not target or target ~= buffer_path then return end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local row = math.max(0, math.min(record.line - 1, line_count - 1))
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
  local column = math.min(record.column, #line)
  local path = record_path(record.root, record.name)
  local existing = tracked[path]
  if existing and vim.api.nvim_buf_is_valid(existing.bufnr) then pcall(vim.api.nvim_buf_del_extmark, existing.bufnr, namespace, existing.id) end
  local id = vim.api.nvim_buf_set_extmark(bufnr, namespace, row, column, { right_gravity = false })
  tracked[path] = { bufnr = bufnr, id = id, record = record }
end

---@param root string
---@return table[]
function M.list(root)
  local directory = root_directory(root)
  if not vim.uv.fs_stat(directory) then return {} end
  local scan_ok, iterator = pcall(vim.fs.dir, directory)
  if not scan_ok then
    warn(('Could not list project marks: %s'):format(iterator))
    return {}
  end

  local records = {}
  for name, kind in iterator do
    if kind == 'file' and name:match '^[0-9a-f]+%.json$' then
      local path = vim.fs.joinpath(directory, name)
      local record, message = decode_record(path, root)
      if record then
        records[#records + 1] = record
      else
        warn(message)
      end
    end
  end
  table.sort(records, function(left, right) return left.name:lower() < right.name:lower() end)
  return records
end

---@param name string
---@param opts? table
---@return boolean
function M.set(name, opts)
  if not valid_name(name) then
    warn 'Mark names must contain printable text and be at most 100 bytes'
    return false
  end
  opts = opts or {}
  local source, message = context(opts.bufnr)
  if not source then
    warn(message)
    return false
  end
  local position = opts.position or vim.api.nvim_win_get_cursor(0)
  local record = {
    schema = 1,
    name = name,
    root = source.root,
    file = source.file,
    line = math.max(1, position[1]),
    column = math.max(0, position[2]),
  }
  local ok, path_or_error = pcall(write_record, record)
  if not ok then
    warn(path_or_error)
    return false
  end
  track(record, source.bufnr)
  vim.notify(('Project mark %q saved'):format(name))
  return true
end

function M.add()
  local source, message = context()
  if not source then return warn(message) end
  local position = vim.api.nvim_win_get_cursor(0)
  vim.ui.input({ prompt = 'Project mark name: ' }, function(name)
    if name == nil then return end
    M.set(name, { bufnr = source.bufnr, position = position })
  end)
end

---@param record table
---@return boolean
function M.jump(record)
  local valid, message, target = validate_record(record, record.root)
  if not valid then
    warn(message)
    return false
  end
  local stat = vim.uv.fs_stat(target)
  if not stat or stat.type ~= 'file' then
    warn(('Project mark %q is stale; target is missing: %s'):format(record.name, target))
    return false
  end

  local path = record_path(record.root, record.name)
  local entry = tracked[path]
  local bufnr
  local position = {}
  if entry and vim.api.nvim_buf_is_valid(entry.bufnr) and vim.api.nvim_buf_is_loaded(entry.bufnr) then
    local buffer_path = project.canonical(vim.api.nvim_buf_get_name(entry.bufnr))
    if buffer_path == target then
      position = vim.api.nvim_buf_get_extmark_by_id(entry.bufnr, namespace, entry.id, {})
      if #position == 2 then bufnr = entry.bufnr end
    end
  end

  pcall(vim.cmd.normal, { args = { "m'" }, bang = true })
  if bufnr then
    if bufnr ~= vim.api.nvim_get_current_buf() then
      local ok, buffer_error = pcall(vim.api.nvim_cmd, { cmd = 'buffer', args = { tostring(bufnr) } }, {})
      if not ok then
        warn(('Could not open project mark %q: %s'):format(record.name, buffer_error))
        return false
      end
    end
  else
    local ok, edit_error = pcall(vim.api.nvim_cmd, { cmd = 'edit', args = { target } }, {})
    if not ok then
      warn(('Could not open project mark %q: %s'):format(record.name, edit_error))
      return false
    end
    bufnr = vim.api.nvim_get_current_buf()
    track(record, bufnr)
    entry = tracked[path]
    if entry then position = vim.api.nvim_buf_get_extmark_by_id(bufnr, namespace, entry.id, {}) end
  end
  local line_count = vim.api.nvim_buf_line_count(0)
  local row = #position == 2 and position[1] + 1 or record.line
  local column = #position == 2 and position[2] or record.column
  row = math.max(1, math.min(row, line_count))
  local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ''
  vim.api.nvim_win_set_cursor(0, { row, math.min(column, #line) })
  vim.cmd.normal { args = { 'zv' }, bang = true }
  return true
end

local function current_root()
  local root = project.buffer_git_root(0)
  if not root then warn 'Current buffer is not a normal file inside a Git repository' end
  return root
end

function M.pick()
  local root = current_root()
  if not root then return end
  local records = M.list(root)
  if #records == 0 then return vim.notify('No project marks in this repository', vim.log.levels.INFO) end
  vim.ui.select(records, {
    prompt = 'Project marks',
    format_item = function(record) return ('%s  %s:%d'):format(record.name, record.file, record.line) end,
  }, function(record)
    if record then M.jump(record) end
  end)
end

function M.delete(name, root)
  root = root or current_root()
  if not root then return false end
  if not valid_name(name) then
    warn 'Mark names must contain printable text and be at most 100 bytes'
    return false
  end
  local path = record_path(root, name)
  if not vim.uv.fs_stat(path) then
    warn(('Project mark does not exist: %s'):format(name))
    return false
  end
  local ok, message = vim.uv.fs_unlink(path)
  if not ok then
    warn(('Could not delete project mark %q: %s'):format(name, message))
    return false
  end
  local entry = tracked[path]
  if entry and vim.api.nvim_buf_is_valid(entry.bufnr) then pcall(vim.api.nvim_buf_del_extmark, entry.bufnr, namespace, entry.id) end
  tracked[path] = nil
  vim.notify(('Project mark %q deleted'):format(name))
  return true
end

function M.select_delete()
  local root = current_root()
  if not root then return end
  local records = M.list(root)
  if #records == 0 then return vim.notify('No project marks in this repository', vim.log.levels.INFO) end
  vim.ui.select(records, {
    prompt = 'Delete project mark',
    format_item = function(record) return ('%s  %s:%d'):format(record.name, record.file, record.line) end,
  }, function(record)
    if record then M.delete(record.name, root) end
  end)
end

local function load_buffer_marks(bufnr)
  local root = project.buffer_git_root(bufnr)
  if not root then return end
  for _, record in ipairs(M.list(root)) do
    track(record, bufnr)
  end
end

vim.api.nvim_create_autocmd('BufReadPost', {
  desc = 'Track loaded project marks through edits',
  group = vim.api.nvim_create_augroup('nvim2-project-marks', { clear = true }),
  callback = function(event) load_buffer_marks(event.buf) end,
})

vim.api.nvim_create_autocmd('BufWritePost', {
  desc = 'Persist project marks moved by saved edits',
  group = 'nvim2-project-marks',
  callback = function(event)
    for path, entry in pairs(tracked) do
      if entry.bufnr == event.buf then
        if not vim.uv.fs_stat(path) then
          tracked[path] = nil
        else
          local disk = decode_record(path, entry.record.root)
          if disk and disk.name == entry.record.name and disk.file == entry.record.file then
            local position = vim.api.nvim_buf_get_extmark_by_id(event.buf, namespace, entry.id, {})
            local line = position[1] and position[1] + 1
            local column = position[2]
            if line and (line ~= entry.record.line or column ~= entry.record.column) then
              disk.line = line
              disk.column = column
              local ok, write_error = pcall(write_record, disk)
              if ok then
                entry.record = disk
              else
                warn(write_error)
              end
            end
          else
            tracked[path] = nil
          end
        end
      end
    end
  end,
})

vim.api.nvim_create_user_command('ProjectMark', function(command)
  if command.args == '' then
    M.add()
  else
    M.set(command.args)
  end
end, { nargs = '?', desc = 'Set or update a project mark' })
vim.api.nvim_create_user_command('ProjectMarks', M.pick, { desc = 'Select a project mark' })
vim.api.nvim_create_user_command('ProjectMarkDelete', function(command)
  if command.args == '' then
    M.select_delete()
  else
    M.delete(command.args)
  end
end, { nargs = '?', desc = 'Delete a project mark' })

vim.keymap.set('n', '<leader>ma', M.add, { desc = '[M]arks [A]dd or update' })
vim.keymap.set('n', '<leader>mm', M.pick, { desc = '[M]arks [M]enu' })
vim.keymap.set('n', '<leader>md', M.select_delete, { desc = '[M]arks [D]elete' })
vim.keymap.set('n', '<leader>sM', M.pick, { desc = '[S]earch project [M]arks' })

return M
