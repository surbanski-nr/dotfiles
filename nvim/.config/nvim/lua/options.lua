require "nvchad.options"

vim.opt.guifont = { "JetBrainsMono Nerd Font", ":h13" }
vim.opt.number = true
vim.opt.relativenumber = true

local o = vim.o
o.verbose = 3
o.verbosefile = "/tmp/nvimlog"
-- o.cursorlineopt = "both" -- to enable cursorline!
