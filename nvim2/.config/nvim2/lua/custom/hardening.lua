-- Kickstart's build hooks execute third-party code after plugin changes.
-- Nvim2 updates plugins without build hooks and provisions tools explicitly.
vim.api.nvim_clear_autocmds { event = 'PackChanged' }
