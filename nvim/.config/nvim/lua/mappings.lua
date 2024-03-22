require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

-- map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

map("n", "<leader>q", "<CMD>q<CR>", { desc = "󰗼 Close" })
map("n", "<leader>qq", "<CMD>qa!<CR>", { desc = "󰗼 Exit" })

map("n", "<leader>as", "<CMD>ASToggle<CR>", { desc = "Auto-save toggle" })
-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")
