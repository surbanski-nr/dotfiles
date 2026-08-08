vim.api.nvim_create_user_command('Nvim2Check', function() vim.cmd 'checkhealth custom' end, {
  desc = 'Check Nvim2 custom configuration, plugins and tools',
})
