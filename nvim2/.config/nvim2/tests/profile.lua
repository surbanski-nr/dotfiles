local M = {}

function M.server(name) return require('custom.lsp').servers[name] ~= nil end

function M.parser(name) return vim.tbl_contains(require('custom.treesitter').parsers, name) end

function M.formatter(name, bufnr) return vim.tbl_contains(require('conform').list_formatters_for_buffer(bufnr or 0), name) end

function M.linter(name, filetype) return vim.tbl_contains(require('lint')._resolve_linter_by_ft(filetype or vim.bo.filetype), name) end

function M.debugger(filetype) return require('dap').configurations[filetype] ~= nil end

return M
