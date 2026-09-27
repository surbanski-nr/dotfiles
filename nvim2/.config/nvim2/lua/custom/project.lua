local M = {}

---@param path string
---@return string?
function M.canonical(path)
  if type(path) ~= 'string' or path == '' then return nil end
  path = vim.fs.normalize(vim.fn.fnamemodify(path, ':p'))

  local resolved = vim.uv.fs_realpath(path)
  if resolved then return vim.fs.normalize(resolved) end

  local missing = {}
  local current = path
  while current and not vim.uv.fs_stat(current) do
    table.insert(missing, 1, vim.fs.basename(current))
    local parent = vim.fs.dirname(current)
    if not parent or parent == current then return nil end
    current = parent
  end

  resolved = current and vim.uv.fs_realpath(current) or nil
  if not resolved then return nil end
  for _, component in ipairs(missing) do
    resolved = vim.fs.joinpath(resolved, component)
  end
  return vim.fs.normalize(resolved)
end

---@param path string
---@return string?
function M.git_root(path)
  local canonical = M.canonical(path)
  if not canonical then return nil end
  local start = canonical
  local stat = vim.uv.fs_stat(start)
  if stat and stat.type ~= 'directory' then
    start = vim.fs.dirname(start)
  else
    while not stat do
      local parent = vim.fs.dirname(start)
      if not parent or parent == start then return nil end
      start = parent
      stat = vim.uv.fs_stat(start)
    end
  end
  local marker = vim.fs.find('.git', { path = start, upward = true })[1]
  return marker and M.canonical(vim.fs.dirname(marker)) or nil
end

---@param bufnr? integer
---@return string?
function M.buffer_git_root(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].buftype ~= '' then return nil end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == '' then return nil end
  return M.git_root(name)
end

return M
