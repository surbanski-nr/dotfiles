require "nvchad.mappings"

-- add yours here
local nomap = vim.keymap.del

nomap("i", "<C-k>")
nomap("n", "<C-k>")

local map = vim.keymap.set

-- map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

map("n", "<leader>qq", "<CMD>qa!<CR>", { desc = "󰗼 Exit" })

map("n", "<leader>al", "<CMD>Lazy<CR>", { desc = "Toggle [L]azy" })

map("n", "<leader>fg", "<CMD>Telescope git_commits<CR>", { desc = "Telescope [G]it History" })
map("n", "<leader>fl", "<CMD>Telescope yaml_schema<CR>", { desc = "Telescope Yam[l] Schema" })

map("n", "gh", "g^", { desc = "Jump to first screen character" })
map("n", "gt", "g$", { desc = "Jump to last screen character" })

map("n", "<leader>aa", function()
  vim.b.x = not vim.b.x
  require("cmp").setup.buffer { enabled = not vim.b.x }
end, { desc = "Toggle [A]uto-completion" })

map("n", "<leader>af", function()
  vim.b.d = not vim.b.d
  if not vim.b.d then
    vim.cmd "windo diffoff"
  else
    vim.cmd "windo diffthis"
  end
end, { desc = "Toggle Di[F]f" })

map("n", "<leader>aq", function()
  local qf_exists = false
  for _, win in pairs(vim.fn.getwininfo()) do
    if win["quickfix"] == 1 then
      qf_exists = true
    end
  end
  if qf_exists == true then
    vim.cmd "cclose"
    return
  end
  if not vim.tbl_isempty(vim.fn.getqflist()) then
    vim.cmd "copen"
  end
end, { desc = "Toggle [Q]uickfix" })

-- map("n", "<leader>uf", function()
--   LazyVim.format.toggle()
-- end, { desc = "Toggle auto format (global)" })
-- map("n", "<leader>uF", function()
--   LazyVim.format.toggle(true)
-- end, { desc = "Toggle auto format (buffer)" })
-- map("n", "<leader>us", function()
--   LazyVim.toggle "spell"
-- end, { desc = "Toggle Spelling" })
-- map("n", "<leader>uw", function()
--   LazyVim.toggle "wrap"
-- end, { desc = "Toggle Word Wrap" })
-- map("n", "<leader>uL", function()
--   LazyVim.toggle "relativenumber"
-- end, { desc = "Toggle Relative Line Numbers" })
-- map("n", "<leader>ul", function()
--   LazyVim.toggle.number()
-- end, { desc = "Toggle Line Numbers" })
-- map("n", "<leader>ud", function()
--   LazyVim.toggle.diagnostics()
-- end, { desc = "Toggle Diagnostics" })

map("n", "<Leader>uo", "<cmd>setlocal nolist!<CR>", { desc = "Toggle Whitespace Symbols" })
map("n", "<Leader>uu", "<cmd>nohlsearch<CR>", { desc = "Hide Search Highlight" })
map("n", "<Leader>ui", vim.show_pos, { desc = "Show Treesitter Node" })

map("n", "<Leader>z", "<cmd>%bd|e#<CR>", { desc = "Close all buffers except current one" })

map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")

map("n", "n", "nzzzv")
map("n", "N", "Nzzzv")
