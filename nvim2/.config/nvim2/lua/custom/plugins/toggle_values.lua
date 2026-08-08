local toggle_values = {
  ['true'] = 'false',
  ['false'] = 'true',
  ['True'] = 'False',
  ['False'] = 'True',
  ['TRUE'] = 'FALSE',
  ['FALSE'] = 'TRUE',
  ['yes'] = 'no',
  ['no'] = 'yes',
  ['Yes'] = 'No',
  ['No'] = 'Yes',
  ['YES'] = 'NO',
  ['NO'] = 'YES',
  ['on'] = 'off',
  ['off'] = 'on',
  ['On'] = 'Off',
  ['Off'] = 'On',
  ['ON'] = 'OFF',
  ['OFF'] = 'ON',
  ['enable'] = 'disable',
  ['disable'] = 'enable',
  ['enabled'] = 'disabled',
  ['disabled'] = 'enabled',
}

local function toggle_value()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]
  local line = vim.api.nvim_get_current_line()
  local index = col + 1

  if not line:sub(index, index):match '[%w_]' then
    vim.notify('Place the cursor on a toggleable value', vim.log.levels.WARN)
    return
  end

  local left, right = index, index
  while left > 1 and line:sub(left - 1, left - 1):match '[%w_]' do
    left = left - 1
  end
  while right <= #line and line:sub(right, right):match '[%w_]' do
    right = right + 1
  end

  local word = line:sub(left, right - 1)
  local replacement = toggle_values[word]
  if not replacement then
    vim.notify(('No toggle configured for %q'):format(word), vim.log.levels.WARN)
    return
  end

  vim.api.nvim_buf_set_text(0, row, left - 1, row, right - 1, { replacement })
  local relative_col = col - (left - 1)
  local new_col = left - 1 + math.min(relative_col, math.max(#replacement - 1, 0))
  vim.api.nvim_win_set_cursor(0, { row + 1, new_col })
end

vim.keymap.set('n', '<leader>tv', toggle_value, { desc = '[T]oggle boolean/[V]alue' })
