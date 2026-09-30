local M = {}

local MAX_QUERY_BYTES = 1024
local MAX_TERMS = 32

local function is_ascii_whitespace(byte) return byte == 32 or (byte >= 9 and byte <= 13) end

local function tokenize(input)
  local tokens = {}
  local token = {}

  local function finish_token()
    if #token == 0 then return end
    tokens[#tokens + 1] = token
    token = {}
  end

  local index = 1
  while index <= #input do
    local byte = input:byte(index)
    if byte == 92 then
      if index < #input then
        index = index + 1
        token[#token + 1] = { value = input:sub(index, index), escaped = true }
      else
        token[#token + 1] = { value = '\\', escaped = true }
      end
    elseif is_ascii_whitespace(byte) then
      finish_token()
    else
      token[#token + 1] = { value = input:sub(index, index), escaped = false }
    end
    index = index + 1
  end

  finish_token()
  return tokens
end

local function is_operator(token, value) return #token == 1 and token[1].value == value and not token[1].escaped end

local function parse_term(token)
  local first = 1
  local last = #token
  local negated = false
  local prefix = false
  local suffix = false

  if first <= last and token[first].value == '!' and not token[first].escaped then
    negated = true
    first = first + 1
  end
  if first <= last and token[first].value == '^' and not token[first].escaped then
    prefix = true
    first = first + 1
  end
  if first <= last and token[last].value == '$' and not token[last].escaped then
    suffix = true
    last = last - 1
  end
  if first > last then return nil end

  local text = {}
  for index = first, last do
    text[#text + 1] = token[index].value
  end
  text = table.concat(text)
  if text == '' then return nil end

  return {
    text = text,
    folded = text:lower(),
    negated = negated,
    prefix = prefix,
    suffix = suffix,
  }
end

function M.parse(input, total_bytes)
  if math.max(#input, total_bytes or 0) > MAX_QUERY_BYTES then return { valid = false, groups = {} } end

  local groups = {}
  local join_next = false
  local term_count = 0

  for _, token in ipairs(tokenize(input)) do
    if is_operator(token, '|') then
      if #groups > 0 then join_next = true end
    else
      local term = parse_term(token)
      if term then
        term_count = term_count + 1
        if term_count > MAX_TERMS then return { valid = false, groups = {} } end

        if join_next and #groups > 0 then
          groups[#groups][#groups[#groups] + 1] = term
        else
          groups[#groups + 1] = { term }
        end
        join_next = false
      end
    end
  end

  return { valid = true, groups = groups }
end

return M
