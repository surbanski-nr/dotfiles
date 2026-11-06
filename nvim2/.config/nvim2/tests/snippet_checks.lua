require 'custom.plugins.snippets'

local function input(filetype, line, keys, expected)
  vim.snippet.stop()
  vim.cmd.enew()
  vim.bo.filetype = filetype
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
  local encoded_keys = vim.api.nvim_replace_termcodes(keys, true, false, true)
  vim.api.nvim_feedkeys(encoded_keys, 'xt', false)
  local actual = vim.api.nvim_get_current_line()
  assert(actual == expected, ('%s input %q in %q produced %q, expected %q'):format(filetype, keys, line, actual, expected))
end

local quote_cases = {
  { '', 'i"ala"<Esc>', '"ala"' },
  { '', 'istring = "ala"<Esc>', 'string = "ala"' },
  { '  ', 'A"<Esc>', '  ""' },
  { 'value', 'A"<Esc>', 'value"' },
  { 'string = "ala', 'A"<Esc>', 'string = "ala"' },
  { 'string = "ala ', 'A"<Esc>', 'string = "ala "' },
  { 'string = "ala" ', 'A"<Esc>', 'string = "ala" "' },
  { '"', 'A"<Esc>', '""' },
  { 'string = "ala"', '$i"x<Esc>', 'string = "ala"x' },
  { 'string = "ala\\"', '$i"<Esc>', 'string = "ala\\""' },
  { 'its', 'lli"<Esc>', 'it"s' },
  { 'value" ', 'A"<Esc>', 'value" "' },
  { '\t', 'A"<Esc>', '\t""' },
}

for _, filetype in ipairs { 'markdown', 'text', 'gitcommit', 'lua', 'python' } do
  for _, text in ipairs {
    "it's",
    "don't change what's already here",
    "'quoted text'",
    '"quoted text"',
  } do
    input(filetype, '', 'i' .. text .. '<Esc>', text)
  end

  for _, quote in ipairs { "'", '"' } do
    for _, case in ipairs(quote_cases) do
      local line = case[1]:gsub('"', quote)
      local keys = case[2]:gsub('"', quote)
      local expected = case[3]:gsub('"', quote)
      input(filetype, line, keys, expected)
    end

    local other_quote = quote == '"' and "'" or '"'
    input(filetype, other_quote .. ' ', 'A' .. quote .. '<Esc>', other_quote .. ' ' .. quote .. quote)
  end

  for _, pair in ipairs {
    { '(value', '(value)' },
    { '[value', '[value]' },
    { '{value', '{value}' },
  } do
    input(filetype, '', 'i' .. pair[1] .. '<Esc>', pair[2])
  end
end

for _, case in ipairs {
  { '*', '*bold', '**bold**' },
  { '_', '_italic', '_italic_' },
} do
  vim.snippet.stop()
  vim.cmd.enew()
  vim.bo.filetype = 'markdown'
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { case[1] .. 'x' })
  vim.api.nvim_win_set_cursor(0, { 1, #case[1] })
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('i' .. case[2] .. '<Esc>', true, false, true), 'xt', false)
  assert(vim.api.nvim_get_current_line() == case[3] .. 'x', 'Markdown formatting expansion changed: ' .. case[1])
end

print 'Nvim2 snippet checks passed'
vim.cmd 'qa!'
