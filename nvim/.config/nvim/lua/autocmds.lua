vim.api.nvim_create_autocmd("FileType", {
  pattern = {
    "gitcommit",
    "markdown",
    "NvimTree",
    "TelescopePrompt",
    "Empty",
  },
  callback = function()
    require("cmp").setup { enabled = false }
  end,
})
vim.api.nvim_create_autocmd("FileType", {
  pattern = {
    "gitcommit",
    "markdown",
  },
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.spell = false
  end,
})
vim.api.nvim_create_autocmd("filetype", {
  pattern = {
    "gitcommit",
    "markdown",
  },
  command = "set nospell",
})
