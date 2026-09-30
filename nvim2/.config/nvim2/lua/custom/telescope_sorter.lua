local M = {}

local query = require 'custom.telescope_query'
local sorters = require 'telescope.sorters'

local function literal_matches(term, candidate)
  if term.prefix and term.suffix then return candidate == term.folded end
  if term.prefix then return candidate:sub(1, #term.folded) == term.folded end
  if term.suffix then return candidate:sub(-#term.folded) == term.folded end
  return candidate:find(term.folded, 1, true) ~= nil
end

local function score_term(base, term, candidate, folded_candidate)
  if term.negated then return literal_matches(term, folded_candidate) and -1 or 1 end
  if (term.prefix or term.suffix) and not literal_matches(term, folded_candidate) then return -1 end
  return base:scoring_function(term.text, candidate)
end

local function score_query(base, parsed, candidate)
  if not parsed.valid then return -1 end
  if #parsed.groups == 0 then return 1 end

  local total = 0
  local folded_candidate
  for _, group in ipairs(parsed.groups) do
    local best
    for _, term in ipairs(group) do
      if (term.negated or term.prefix or term.suffix) and not folded_candidate then folded_candidate = candidate:lower() end
      local score = score_term(base, term, candidate, folded_candidate)
      if score >= 0 and (not best or score < best) then best = score end
    end
    if not best then return -1 end
    total = total + best
  end
  return total
end

local function add_interval(intervals, start, finish)
  if start and finish and start >= 1 and finish >= start then intervals[#intervals + 1] = { start = start, finish = finish } end
end

local function add_literal_highlights(intervals, term, folded_display)
  local offset = 1
  while offset <= #folded_display do
    local start, finish = folded_display:find(term.folded, offset, true)
    if not start then return end
    add_interval(intervals, start, finish)
    offset = start + 1
  end
end

local function add_fuzzy_highlights(intervals, base, term, display)
  if base:scoring_function(term.text, display) < 0 then return end
  for _, position in ipairs(base:highlighter(term.text, display) or {}) do
    if type(position) == 'number' then
      add_interval(intervals, position, position)
    elseif type(position) == 'table' then
      add_interval(intervals, position.start, position.finish or position.start)
    end
  end
end

local function merge_intervals(intervals)
  table.sort(intervals, function(left, right)
    if left.start == right.start then return left.finish < right.finish end
    return left.start < right.start
  end)

  local merged = {}
  for _, interval in ipairs(intervals) do
    local previous = merged[#merged]
    if previous and interval.start <= previous.finish + 1 then
      previous.finish = math.max(previous.finish, interval.finish)
    else
      merged[#merged + 1] = interval
    end
  end
  return merged
end

local function highlight_query(base, parsed, display)
  if not parsed.valid or #parsed.groups == 0 then return {} end

  local intervals = {}
  local folded_display = display:lower()
  for _, group in ipairs(parsed.groups) do
    for _, term in ipairs(group) do
      if not term.negated then
        if term.prefix or term.suffix then
          add_literal_highlights(intervals, term, folded_display)
        else
          add_fuzzy_highlights(intervals, base, term, display)
        end
      end
    end
  end
  return merge_intervals(intervals)
end

function M.new(opts)
  local base = sorters.get_fzy_sorter(opts)
  local state = { generation = 0 }

  local function clear_query()
    state.raw_prompt = nil
    state.effective_prompt = nil
    state.parsed = nil
    state.parsed_generation = nil
  end

  return sorters.Sorter:new {
    discard = false,
    init = function() clear_query() end,
    start = function(_, raw_prompt)
      state.generation = state.generation + 1
      clear_query()
      state.raw_prompt = raw_prompt
    end,
    destroy = function()
      state.generation = state.generation + 1
      clear_query()
    end,
    scoring_function = function(_, effective_prompt, candidate)
      if state.raw_prompt == nil then return -1 end
      if state.effective_prompt ~= effective_prompt or state.parsed_generation ~= state.generation then
        state.effective_prompt = effective_prompt
        state.parsed = query.parse(effective_prompt, #state.raw_prompt)
        state.parsed_generation = state.generation
      end
      return score_query(base, state.parsed, candidate)
    end,
    highlighter = function(_, raw_prompt, display)
      if raw_prompt ~= state.raw_prompt or state.parsed_generation ~= state.generation or type(display) ~= 'string' then return {} end
      return highlight_query(base, state.parsed, display)
    end,
  }
end

return M
