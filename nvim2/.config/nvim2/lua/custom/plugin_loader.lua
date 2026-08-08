local M = {}

---@param directory string
---@return string[] modules
---@return string[] broken_links
function M.scan(directory)
  local modules = {}
  local broken_links = {}

  for file_name, entry_type in vim.fs.dir(directory) do
    if file_name:match '%.lua$' and file_name ~= 'init.lua' then
      local path = vim.fs.joinpath(directory, file_name)
      if entry_type == 'file' or (entry_type == 'link' and vim.uv.fs_stat(path)) then
        table.insert(modules, (file_name:gsub('%.lua$', '')))
      elseif entry_type == 'link' then
        table.insert(broken_links, path)
      end
    end
  end

  table.sort(modules)
  table.sort(broken_links)
  return modules, broken_links
end

return M
