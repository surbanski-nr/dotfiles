require "nvchad.mappings"

-- map("i", "<C-b>", "<ESC>^i", { desc = "move beginning of line" })
-- map("i", "<C-e>", "<End>", { desc = "move end of line" })
-- map("t", "<C-x>", "<C-\\><C-N>", { desc = "terminal escape terminal mode" })
-- n / p / h / v
--
local nomap = vim.keymap.del

nomap("n", "<leader>fm")
nomap("n", "<leader>n")
nomap("n", "<leader>rn")
nomap("n", "<leader>ch")
-- nomap("n", "<leader>lf")
nomap("n", "<leader>ds")
-- nomap("n", "<leader>q")
nomap("n", "<leader>cm")
nomap("n", "<leader>ma")
nomap("n", "<leader>gt")
nomap("n", "<leader>pt")
nomap("n", "<leader>h")
nomap("n", "<leader>v")
-- nomap("n", "<leader>ra")
-- nomap("n", "<leader>D")
-- nomap("n", "<leader>wa")
-- nomap("n", "<leader>wl")
-- nomap("n", "<leader>wr")
-- nomap("n", "<leader>sh")

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })

map("i", "jk", "<ESC>")

map("n", "J", "mzJ`z", { desc = "Join line" })

-- Don't leave visual mode when changing indent
map("x", ">", ">gv", { noremap = true })
map("x", "<", "<gv", { noremap = true })

map("i", "<C-BS>", "<Esc>cvb", { desc = "Delete previous word" })

map("n", "<leader>+", "<C-a>", { desc = "Increment number" })
map("n", "<leader>-", "<C-x>", { desc = "Decrement number" })

map("n", "<leader>qq", "<CMD>qa!<CR>", { desc = "󰗼 Exit" })

map("n", "<leader>al", "<CMD>Lazy<CR>", { desc = "Toggle [L]azy" })

map("n", "<leader>sr", function()
  require "nvchad.lsp.renamer"()
end, { desc = "NvRenamer" })

map("n", "<leader>ch", vim.lsp.buf.signature_help, { desc = "Show signature help" }, "Show signature help")

map("n", "<leader>fc", "<CMD>Telescope git_commits<CR>", { desc = "Telescope Git [C]ommits" })
map("n", "<leader>fs", "<CMD>Telescope git_status<CR>", { desc = "Telescope Git [S]tatus" })
map("n", "<leader>fm", "<CMD>Telescope marks<CR>", { desc = "Telescope [M]arks" })
map("n", "<leader>fl", "<CMD>Telescope yaml_schema<CR>", { desc = "Telescope Yam[l] Schema" })

map("n", "gh", "g^", { desc = "Jump to first screen character" })
map("n", "gt", "g$", { desc = "Jump to last screen character" })

map("n", "gO", "<Cmd>call append(line('.') - 1, repeat([''], v:count1))<CR>")
map("n", "go", "<Cmd>call append(line('.'),     repeat([''], v:count1))<CR>")

map("n", "gm", function()
  require("conform").format { lsp_fallback = true }
end, { desc = "Format files" })

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

map("n", "<Leader>z", "<cmd>%bd|e#<CR>", { desc = "Close all buffers except current one" })

map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")

map("n", "<A-j>", "<cmd>m .+1<CR>==", { desc = "move the line up", silent = true })
map("n", "<A-k>", "<cmd>m .-2<CR>==", { desc = "move the line down", silent = true })
map("v", "<A-j>", "<cmd>m '>+1<CR>gv=gv", { desc = "move the selected text up", silent = true })
map("v", "<A-k>", "<cmd>m '<-2<CR>gv=gv", { desc = "move the selected text down", silent = true })

map("n", "n", "nzzzv")
map("n", "N", "Nzzzv")
