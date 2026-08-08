local M = {}

function M.setup()
  vim.api.nvim_create_user_command('FormatDisable', function(args)
    if args.bang then
      vim.b.disable_autoformat = true
    else
      vim.g.disable_autoformat = true
    end
  end, { bang = true, desc = 'Disable format-on-save' })

  vim.api.nvim_create_user_command('FormatEnable', function(args)
    if args.bang then
      vim.b.disable_autoformat = false
    else
      vim.g.disable_autoformat = false
    end
  end, { bang = true, desc = 'Enable format-on-save' })

  vim.api.nvim_create_user_command('FormatToggle', function()
    vim.g.disable_autoformat = not vim.g.disable_autoformat
    local state = vim.g.disable_autoformat and 'disabled' or 'enabled'
    vim.notify('Format-on-save ' .. state .. ' for this Neovim session')
  end, { desc = 'Toggle format-on-save for this Neovim session' })

  vim.keymap.set('n', '<leader>tf', '<Cmd>FormatToggle<CR>', { desc = '[T]oggle [F]ormat-on-save' })

  require('conform').setup {
    notify_on_error = false,
    format_on_save = function(bufnr)
      if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then return nil end

      local enabled_filetypes = {
        bash = true,
        css = true,
        dockerfile = true,
        graphql = true,
        handlebars = true,
        html = true,
        javascript = true,
        json = true,
        jsonc = true,
        less = true,
        lua = true,
        markdown = true,
        python = true,
        scss = true,
        sh = true,
        svelte = true,
        terraform = true,
        ['terraform-vars'] = true,
        toml = true,
        typescript = true,
        vue = true,
        yaml = true,
        ['yaml.ansible'] = true,
        ['yaml.docker-compose'] = true,
        ['yaml.helm-values'] = true,
      }
      if enabled_filetypes[vim.bo[bufnr].filetype] then return { timeout_ms = 1000 } end
    end,
    default_format_opts = {
      lsp_format = 'fallback',
    },
    formatters_by_ft = {
      bash = { 'shfmt' },
      css = { 'prettier' },
      graphql = { 'prettier' },
      handlebars = { 'prettier' },
      html = { 'prettier' },
      javascript = { 'prettier' },
      json = { 'prettier' },
      jsonc = { 'prettier' },
      less = { 'prettier' },
      lua = { 'stylua' },
      markdown = { 'prettier' },
      python = { 'ruff_organize_imports', 'ruff_format' },
      scss = { 'prettier' },
      sh = { 'shfmt' },
      svelte = { 'prettier' },
      terraform = { 'terraform_fmt' },
      ['terraform-vars'] = { 'terraform_fmt' },
      toml = { 'taplo' },
      typescript = { 'prettier' },
      vue = { 'prettier' },
      yaml = { 'yamlfmt' },
      ['yaml.ansible'] = { 'yamlfmt' },
      ['yaml.docker-compose'] = { 'yamlfmt' },
      ['yaml.helm-values'] = { 'yamlfmt' },
    },
  }

  vim.keymap.set({ 'n', 'v' }, '<leader>f', function() require('conform').format { async = true } end, { desc = '[F]ormat buffer' })
end

return M
