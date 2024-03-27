---@type ChadrcConfig
local M = {}

M.ui = {
  theme = "github_dark",

  statusline = {
    -- order = { "copilot", "mode", "file", "git", "%=", "lsp_msg", "%=", "diagnostics", "lsp", "cwd", "cursor" },
    --   theme = "minimal",
    --   separator_style = "round",
    --   overriden_modules = nil,
  },

  -- telescope = { style = "bordered" },

  hl_override = {
    Comment = { italic = true },
    ["@comment"] = { italic = true },
  },
}

return M
