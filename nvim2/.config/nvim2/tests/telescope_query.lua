local function run()
  local query_sorter = require 'custom.telescope_sorter'
  local telescope_sorters = require 'telescope.sorters'

  local function new_sorter()
    local sorter = query_sorter.new {}
    sorter:_init()
    return sorter
  end

  local function score(sorter, prompt, candidate, fields)
    local entry = vim.tbl_extend('force', { ordinal = candidate }, fields or {})
    local result
    sorter:score(prompt, entry, function(value) result = value end, function() result = -1 end)
    return result
  end

  local function scores(prompt, candidates)
    local sorter = new_sorter()
    sorter:_start(prompt)
    local result = {}
    for _, candidate in ipairs(candidates) do
      result[candidate] = score(sorter, prompt, candidate)
    end
    sorter:_finish(prompt)
    return result
  end

  local function assert_accepts(prompt, accepted, rejected)
    local candidates = vim.list_extend(vim.deepcopy(accepted), rejected)
    local result = scores(prompt, candidates)
    for _, candidate in ipairs(accepted) do
      assert(result[candidate] and result[candidate] >= 0, ('query %q rejected %q'):format(prompt, candidate))
    end
    for _, candidate in ipairs(rejected) do
      assert(result[candidate] == -1, ('query %q accepted %q with score %s'):format(prompt, candidate, result[candidate]))
    end
  end

  for _, case in ipairs {
    { 'foo', { 'foo', 'src/Foo.lua', 'far_out_of_order' }, { '', 'bar', '   ' } },
    { 'foo bar', { 'bar before foo', 'food/barn' }, { 'foo only', 'bar only' } },
    { 'foo | bar baz', { 'foo baz', 'bar baz' }, { 'foo', 'bar', 'baz' } },
    { '^src/', { 'src/main.lua', 'SRC/view.vim' }, { 'lib/src/main.lua', 'source/main.lua' } },
    { '.lua$', { 'src/main.lua', 'MAIN.LUA' }, { 'src/main.lua.bak', 'lua' } },
    { '^README.md$', { 'README.md', 'readme.MD' }, { 'docs/README.md', 'README.md.bak' } },
    { '!test', { 'src/main.lua', '' }, { 'src/main_test.lua', 'TEST/main.lua' } },
    { '!^test/', { 'src/test/main.lua', 'contest/main.lua' }, { 'test/main.lua', 'TEST/unit.lua' } },
    { '!_test.lua$', { 'src/test.lua', 'src/_test.lua.bak' }, { 'src/main_test.lua' } },
    { '!^README.md$', { 'docs/README.md', 'README.md.bak' }, { 'README.md', 'readme.MD' } },
    { 'foo | !test', { 'foo_test', 'plain', 'foo' }, { 'test-only' } },
    { 'alphabet', {}, { '', 'alpha', '   ' } },
  } do
    assert_accepts(case[1], case[2], case[3])
  end

  assert_accepts('^src/ .lua$ | .vim$ !test', { 'src/main.lua', 'src/view.vim' }, {
    'src/main_test.lua',
    'docs/main.lua',
    'test/main.lua',
    'src/lua.notes',
  })

  for byte = 9, 13 do
    assert_accepts('foo' .. string.char(byte) .. 'bar', { 'foo bar' }, { 'foo', 'bar' })
  end

  for _, case in ipairs {
    { [[\!note]], { 'draft !note' }, { 'draft note' } },
    { [[\^draft]], { 'notes/^draft.txt' }, { 'draft.txt' } },
    { [[file\$]], { 'tmp/file$' }, { 'tmp/file' } },
    { [[\|]], { 'left|right' }, { 'left right' } },
    { [[a\ b]], { 'prefix a b suffix' }, { 'ab' } },
    { [[\\]], { [[path\name]] }, { 'pathname' } },
    { [[tail\]], { [[a tail\]] }, { 'a tail' } },
    { 'foo|bar', { 'foo|bar' }, { 'foo bar', 'foobar' } },
    { '"foo"', { 'a "foo" value' }, { 'foo' } },
  } do
    assert_accepts(case[1], case[2], case[3])
  end

  for _, prompt in ipairs { '', '   \t\r\n', '|', '!', '^', '$', '!^', '!$', '^$', '!^$', 'foo |', '| foo', 'foo !' } do
    local accepted = prompt:find('foo', 1, true) and { 'foo' } or { '', 'anything' }
    assert_accepts(prompt, accepted, prompt:find('foo', 1, true) and { 'bar' } or {})
  end
  assert_accepts('foo | | bar', { 'foo', 'bar' }, { 'baz' })
  assert_accepts('foo | ! bar', { 'foo', 'bar' }, { 'baz' })

  local thirty_two = {}
  for _ = 1, 32 do
    thirty_two[#thirty_two + 1] = 'a'
  end
  assert_accepts(table.concat(thirty_two, ' '), { 'a' }, { 'b' })
  thirty_two[#thirty_two + 1] = 'a'

  local over_terms = new_sorter()
  local over_terms_prompt = table.concat(thirty_two, ' ')
  over_terms:_start(over_terms_prompt)
  assert(score(over_terms, over_terms_prompt, 'a') == -1, '33 terms did not reject all results')

  local exact_limit = string.rep('a', 1024)
  assert_accepts(exact_limit, { exact_limit }, { 'a' })
  local over_limit = string.rep('a', 1025)
  local limited = new_sorter()
  limited:_start(over_limit)
  assert(score(limited, over_limit, over_limit) == -1, '1,025-byte query did not reject all results')

  local base = telescope_sorters.get_fzy_sorter {}
  for _, prompt in ipairs { 'foo', 'src', 'ml' } do
    for _, candidate in ipairs { 'foo', 'src/foo.lua', 'far_out_of_order', 'README.md' } do
      local adapter_score = scores(prompt, { candidate })[candidate]
      local base_score = base:scoring_function(prompt, candidate)
      assert(adapter_score == base_score, ('single-term score changed for %q and %q'):format(prompt, candidate))
    end
  end

  local ranked_candidate = 'src/foobar.lua'
  local foo_score = base:scoring_function('foo', ranked_candidate)
  local bar_score = base:scoring_function('bar', ranked_candidate)
  assert(scores('foo bar', { ranked_candidate })[ranked_candidate] == foo_score + bar_score, 'AND scores were not summed')
  assert(scores('foo | bar', { ranked_candidate })[ranked_candidate] == math.min(foo_score, bar_score), 'OR did not choose its best score')
  assert(scores('^src/', { ranked_candidate })[ranked_candidate] == base:scoring_function('src/', ranked_candidate), 'anchor changed fzy score')
  assert(scores('foo !test', { ranked_candidate })[ranked_candidate] == foo_score + 1, 'accepted negation did not contribute score 1')

  local negative = new_sorter()
  negative:_start '!test'
  assert(score(negative, '!test', 'main.lua') == 1, 'accepted negation did not score 1')
  assert(score(negative, '!test', 'other.lua') == 1, 'accepted negations did not have a fixed score')
  assert(vim.deep_equal(negative:highlighter('!test', 'main.lua'), {}), 'negation produced highlighting')

  local changing = new_sorter()
  changing:_start 'foo'
  assert(score(changing, 'foo', 'bar') == -1, 'foo unexpectedly accepted bar')
  changing:_finish 'foo'
  changing:_start 'foo | bar'
  assert(score(changing, 'foo | bar', 'bar') >= 0, 'adding OR did not restore bar')
  changing:_finish 'foo | bar'
  changing:_start '!a'
  assert(score(changing, '!a', 'cat') == -1, '!a unexpectedly accepted cat')
  changing:_finish '!a'
  changing:_start '!ab'
  assert(score(changing, '!ab', 'cat') == 1, 'extending negation did not restore cat')
  changing:_finish '!ab'
  changing:_start ''
  assert(score(changing, '', 'bar') == 1, 'deleting the query did not restore all results')
  changing:_finish ''
  changing:_start 'foo'
  assert(score(changing, 'foo', 'foo') == 0, 'retyping a query did not restore matching')

  local function coverage(ranges)
    local covered = {}
    for _, range in ipairs(ranges) do
      for index = range.start, range.finish do
        covered[index] = true
      end
    end
    return covered
  end

  local function assert_highlighted(prompt, ordinal, display, needles)
    local sorter = new_sorter()
    sorter:_start(prompt)
    assert(score(sorter, prompt, ordinal) >= 0, ('highlight fixture did not match %q'):format(prompt))
    local ranges = sorter:highlighter(prompt, display)
    local covered = coverage(ranges)
    for _, needle in ipairs(needles) do
      local start, finish = display:lower():find(needle:lower(), 1, true)
      assert(start, ('highlight fixture %q lacks %q'):format(display, needle))
      for index = start, finish do
        assert(covered[index], ('query %q did not highlight byte %d of %q'):format(prompt, index, display))
      end
    end
    return ranges
  end

  assert_highlighted('foo | bar', 'foo', 'icon foo and bar', { 'foo', 'bar' })
  local syntax_coverage = coverage(assert_highlighted('foo | bar', 'foo', 'foo | bar', { 'foo', 'bar' }))
  assert(not syntax_coverage[5], 'OR syntax was highlighted')
  assert_highlighted('^src/', 'src/main.lua', 'ICON src/main.lua', { 'src/' })
  assert_highlighted([[\|]], 'left|right', 'icon | item', { '|' })
  local utf8_ranges = assert_highlighted('é$', 'café', 'icon café', { 'é' })
  assert(#utf8_ranges > 0, 'UTF-8 literal highlight is missing')
  local overlap = assert_highlighted('foo | oo', 'foo', 'foo', { 'foo' })
  assert(#overlap == 1 and overlap[1].start == 1 and overlap[1].finish == 3, 'overlapping highlights were not merged')

  local long_display = string.rep('a', 1024) .. 'z'
  local long_sorter = new_sorter()
  long_sorter:_start 'z'
  assert(score(long_sorter, 'z', long_display) == 1, 'long fzy candidate did not keep the base worst score')
  assert(vim.deep_equal(long_sorter:highlighter('z', long_display), {}), 'long fzy display guessed highlight positions')

  local stale = new_sorter()
  stale:_start 'foo'
  assert(score(stale, 'foo', 'foo') >= 0, 'stale-state fixture did not match')
  assert(#stale:highlighter('foo', 'foo') > 0, 'initial highlight state is missing')
  stale:_start 'bar'
  assert(vim.deep_equal(stale:highlighter('bar', 'bar'), {}), 'new prompt reused stale highlights before scoring')
  assert(score(stale, 'bar', 'bar') >= 0, 'new prompt did not score')
  assert(#stale:highlighter('bar', 'bar') > 0, 'new prompt did not establish highlights')
  stale:_destroy()
  assert(vim.deep_equal(stale:highlighter('bar', 'bar'), {}), 'destroyed sorter retained highlight state')

  local first = new_sorter()
  local second = new_sorter()
  first:_start 'foo'
  second:_start 'bar'
  assert(score(first, 'foo', 'foo') >= 0 and score(second, 'bar', 'bar') >= 0, 'independent sorter fixture did not score')
  assert(vim.deep_equal(first:highlighter('bar', 'bar'), {}), 'first sorter used the second sorter prompt')
  assert(vim.deep_equal(second:highlighter('foo', 'foo'), {}), 'second sorter used the first sorter prompt')

  local prefiltered = telescope_sorters.prefilter {
    tag = 'symbol_type',
    sorter = new_sorter(),
  }
  local symbol_prompt = ':function: foo | bar'
  prefiltered:_start(symbol_prompt)
  assert(score(prefiltered, symbol_prompt, 'bar Function', { symbol_type = 'Function' }) >= 0, 'prefilter removed a valid symbol')
  assert(score(prefiltered, symbol_prompt, 'bar Variable', { symbol_type = 'Variable' }) == -1, 'prefilter accepted the wrong symbol kind')
  local symbol_ranges = prefiltered:highlighter(symbol_prompt, 'ƒ foo bar function')
  local symbol_coverage = coverage(symbol_ranges)
  local foo_start = assert(('ƒ foo bar function'):find('foo', 1, true))
  local bar_start = assert(('ƒ foo bar function'):find('bar', 1, true))
  assert(symbol_coverage[foo_start] and symbol_coverage[bar_start], 'prefilter highlight did not use the effective query')
  prefiltered:_finish(symbol_prompt)
  local changed_symbol_prompt = ':function: bar'
  prefiltered:_start(changed_symbol_prompt)
  assert(vim.deep_equal(prefiltered:highlighter(changed_symbol_prompt, 'ƒ foo bar function'), {}), 'prefilter retained stale highlights')
  assert(score(prefiltered, changed_symbol_prompt, 'bar Function', { symbol_type = 'Function' }) >= 0, 'changed prefilter query did not match')
  local changed_symbol_coverage = coverage(prefiltered:highlighter(changed_symbol_prompt, 'ƒ foo bar function'))
  assert(changed_symbol_coverage[bar_start] and not changed_symbol_coverage[foo_start], 'prefilter highlighted a stale effective query')

  local raw_limit_prompt = ':function: ' .. string.rep('a', 1014)
  local raw_limited = telescope_sorters.prefilter {
    tag = 'symbol_type',
    sorter = new_sorter(),
  }
  raw_limited:_start(raw_limit_prompt)
  assert(
    score(raw_limited, raw_limit_prompt, string.rep('a', 1014) .. ' Function', { symbol_type = 'Function' }) == -1,
    'prefilter bypassed the whole-prompt byte limit'
  )

  local pickers = require 'telescope.pickers'
  local finders = require 'telescope.finders'
  local actions = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'

  local function wait_for_results(picker, expected, label)
    assert(vim.wait(3000, function() return picker.manager and picker.manager:num_results() == expected end), label)
  end

  local picker = pickers.new({
    default_text = 'foo',
    cache_picker = { num_pickers = 1, limit_entries = 20, ignore_empty_prompt = false },
  }, {
    prompt_title = 'Query transition regression',
    finder = finders.new_table { results = { 'foo', 'bar', 'cat' } },
    sorter = require('telescope.config').values.generic_sorter {},
  })
  picker:find()
  wait_for_results(picker, 1, 'real picker did not filter foo')
  picker:set_prompt 'foo | bar'
  wait_for_results(picker, 2, 'real picker did not restore bar after OR')
  picker:set_prompt '!a'
  wait_for_results(picker, 1, 'real picker did not filter !a')
  picker:set_prompt '!ab'
  wait_for_results(picker, 3, 'real picker did not restore cat after extending negation')
  picker:set_prompt ''
  wait_for_results(picker, 3, 'real picker did not restore results after deleting the prompt')
  picker:set_prompt 'foo'
  wait_for_results(picker, 1, 'real picker did not filter after retyping')
  actions.close(picker.prompt_bufnr)
  require('telescope.builtin').resume()
  assert(vim.wait(3000, function() return vim.bo.filetype == 'TelescopePrompt' end), 'cached picker did not resume')
  local resumed_prompt = vim.api.nvim_get_current_buf()
  local resumed = action_state.get_current_picker(resumed_prompt)
  wait_for_results(resumed, 1, 'resumed picker did not restore its query result')
  assert(resumed.manager:get_entry(1).ordinal == 'foo', 'resumed picker selected a stale result')
  actions.close(resumed_prompt)

  local fixture = vim.fn.tempname()
  assert(vim.fn.mkdir(vim.fs.joinpath(fixture, 'src'), 'p') == 1, 'could not create Telescope file fixture')
  assert(vim.fn.mkdir(vim.fs.joinpath(fixture, 'docs'), 'p') == 1, 'could not create Telescope docs fixture')
  for _, path in ipairs {
    'src/main.lua',
    'src/view.vim',
    'src/main_test.lua',
    'docs/main.lua',
    'src/lua.notes',
  } do
    vim.fn.writefile({ path }, vim.fs.joinpath(fixture, path))
  end

  require('telescope.builtin').find_files {
    cwd = fixture,
    default_text = '^src/ .lua$ | .vim$ !test',
    find_command = { 'rg', '--files' },
    previewer = false,
  }
  assert(vim.wait(3000, function() return vim.bo.filetype == 'TelescopePrompt' end), 'real file picker did not open')
  local file_prompt = vim.api.nvim_get_current_buf()
  local file_picker = action_state.get_current_picker(file_prompt)
  wait_for_results(file_picker, 2, 'real file picker returned the wrong query results')
  local file_ordinals = { file_picker.manager:get_ordinal(1), file_picker.manager:get_ordinal(2) }
  table.sort(file_ordinals)
  assert(vim.deep_equal(file_ordinals, { 'src/main.lua', 'src/view.vim' }), 'real file picker filtered the wrong ordinals')
  vim.fn.setqflist({}, 'r')
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-q>', true, false, true), 'xt', false)
  assert(vim.wait(3000, function() return #vim.fn.getqflist() == 2 end), 'operator-filtered files were not exported to quickfix')
  vim.cmd.cclose()
  vim.fn.delete(fixture, 'rf')

  vim.cmd.enew()
  local buffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(buffer, '/tmp/nvim2-telescope-query.lua')
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'foo alpha', 'bar beta', 'foo test' })
  require('telescope.builtin').current_buffer_fuzzy_find { default_text = 'foo | bar !test', previewer = false }
  assert(vim.wait(3000, function() return vim.bo.filetype == 'TelescopePrompt' end), 'real current-buffer picker did not open')
  local buffer_prompt = vim.api.nvim_get_current_buf()
  local buffer_picker = action_state.get_current_picker(buffer_prompt)
  wait_for_results(buffer_picker, 2, 'real current-buffer picker returned the wrong query results')
  local buffer_ordinals = { buffer_picker.manager:get_ordinal(1), buffer_picker.manager:get_ordinal(2) }
  table.sort(buffer_ordinals)
  assert(vim.deep_equal(buffer_ordinals, { 'bar beta', 'foo alpha' }), 'current-buffer picker filtered the wrong ordinals')
  actions.close(buffer_prompt)
  vim.api.nvim_buf_delete(buffer, { force = true })

  io.stdout:write 'Telescope query checks passed\n'
end

return run
