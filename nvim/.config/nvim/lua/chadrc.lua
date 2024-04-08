---@type ChadrcConfig
local M = {}

M.ui = {
  theme = "github_dark",

  statusline = {
    order = {
      "mode",
      "file",
      "git",
      "%=",
      "lsp_msg",
      "%=",
      "diagnostics",
      "lsp",
      "yaml_schema",
      "pomo",
      "copilot",
      "cwd",
      "cursor",
    },
    modules = {
      copilot = function()
        return "/ " .. require("copilot_status").status_string() .. " "
      end,
      yaml_schema = function()
        local schema = require("yaml-companion").get_buf_schema(0)
        if schema.result[1].name == "none" then
          return ""
        end
        return "/ 󰨁 " .. schema.result[1].name .. " "
      end,
      pomo = function()
        local ok, pomo = pcall(require, "pomo")
        if not ok then
          return ""
        end
        local timer = pomo.get_first_to_finish()
        if timer == nil then
          return ""
        end
        return "/ 󰄉 " .. tostring(timer) .. " "
      end,
    },
    --   theme = "minimal",
    separator_style = "round",
  },

  -- telescope = { style = "bordered" },

  -- hl_override = {
  --   Comment = { italic = true },
  --   ["@comment"] = { italic = true },
  -- },
}

return M
