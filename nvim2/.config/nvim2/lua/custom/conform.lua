local M = {}

function M.is_enabled(bufnr)
  local disabled = vim.b[bufnr or 0].disable_autoformat
  if disabled == nil then disabled = vim.g.disable_autoformat end
  return not disabled
end

local function set_disabled(disabled, buffer_only)
  if buffer_only then
    vim.b.disable_autoformat = disabled
  else
    vim.g.disable_autoformat = disabled
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      vim.b[bufnr].disable_autoformat = nil
    end
  end
  local state = M.is_enabled() and 'enabled' or 'disabled'
  local scope = buffer_only and 'this buffer' or 'this Neovim session'
  vim.notify('Format on save ' .. state .. ' for ' .. scope)
end

function M.setup()
  if vim.g.disable_autoformat == nil then vim.g.disable_autoformat = true end

  vim.api.nvim_create_user_command(
    'FormatDisable',
    function(args) set_disabled(true, args.bang) end,
    { bang = true, desc = 'Disable format on save (bang: current buffer)' }
  )

  vim.api.nvim_create_user_command(
    'FormatEnable',
    function(args) set_disabled(false, args.bang) end,
    { bang = true, desc = 'Enable format on save (bang: current buffer)' }
  )

  vim.api.nvim_create_user_command('FormatToggle', function(args)
    local disabled = not vim.g.disable_autoformat
    if args.bang then disabled = M.is_enabled() end
    set_disabled(disabled, args.bang)
  end, { bang = true, desc = 'Toggle format on save (bang: current buffer)' })

  vim.keymap.set('n', '<leader>tf', '<Cmd>FormatToggle<CR>', { desc = '[T]oggle [F]ormat on save for this session' })

  require('conform').setup {
    notify_on_error = false,
    format_on_save = function(bufnr)
      if not M.is_enabled(bufnr) or not vim.bo[bufnr].modifiable then return nil end

      local enabled_filetypes = {
        bash = true,
        css = true,
        dockerfile = true,
        go = true,
        graphql = true,
        handlebars = true,
        html = true,
        javascript = true,
        javascriptreact = true,
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
        typescriptreact = true,
        vue = true,
        yaml = true,
        ['yaml.ansible'] = true,
        ['yaml.docker-compose'] = true,
        ['yaml.helm-values'] = true,
      }
      if enabled_filetypes[vim.bo[bufnr].filetype] then return { bufnr = bufnr, timeout_ms = 1000 } end
    end,
    default_format_opts = {
      lsp_format = 'fallback',
    },
    formatters = {
      goimports = { env = require('custom.go').env },
      yamlfmt = { prepend_args = { '-formatter', 'retain_line_breaks=true' } },
    },
    formatters_by_ft = {
      bash = { 'shfmt' },
      css = { 'prettier' },
      go = { 'goimports' },
      graphql = { 'prettier' },
      handlebars = { 'prettier' },
      html = { 'prettier' },
      javascript = { 'prettier' },
      javascriptreact = { 'prettier' },
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
      typescriptreact = { 'prettier' },
      vue = { 'prettier' },
      yaml = { 'yamlfmt' },
      ['yaml.ansible'] = { 'yamlfmt' },
      ['yaml.docker-compose'] = { 'yamlfmt' },
      ['yaml.helm-values'] = { 'yamlfmt' },
    },
  }

  vim.keymap.set({ 'n', 'v' }, '<leader>f', function()
    if not vim.bo.modifiable then return end
    require('conform').format { async = true }
  end, { desc = '[F]ormat buffer or selection once' })
end

return M
