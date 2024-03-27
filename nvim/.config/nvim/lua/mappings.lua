require "nvchad.mappings"

-- add yours here
local nomap = vim.keymap.del

nomap("i", "<C-k>")
nomap("n", "<C-k>")

local map = vim.keymap.set

-- map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

map("n", "<leader>qq", "<CMD>qa!<CR>", { desc = "󰗼 Exit" })

map("n", "<leader>ll", "<CMD>Lazy<CR>", { desc = "Lazy" })

map("n", "<leader>fg", "<CMD>Telescope git_commits<CR>", { desc = "Telescope Git History" })

map("n", "gh", "g^", { desc = "Jump to first screen character" })
map("n", "gt", "g$", { desc = "Jump to last screen character" })

map("n", "<leader>as", "<CMD>ASToggle<CR>", { desc = "Auto-save toggle" })

map("n", "<M-c>", "<CMD>CopilotChatToggle<CR>", { desc = "Copilot chat toggle" })

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
