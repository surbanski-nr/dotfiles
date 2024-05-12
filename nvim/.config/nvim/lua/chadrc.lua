---@type ChadrcConfig
local M = {}

M.ui = {
  theme = "github_dark",
  theme_toggle = { "github_dark", "github_light" },

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
        local ok, copilot = pcall(require, "copilot_status")
        if not ok then
          return ""
        end
        local status = copilot.status_string()
        if status == nil then
          return ""
        end
        return "| " .. status .. " "
      end,
      yaml_schema = function()
        local ok, yamlcomp = pcall(require, "yaml-companion")
        if not ok then
          return ""
        end
        local schema = yamlcomp.get_buf_schema(0)
        if schema.result[1].name == "none" then
          return ""
        end
        return "| 󰨁 " .. schema.result[1].name .. " "
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
        return "| 󰄉 " .. tostring(timer) .. " "
      end,
    },
    -- theme = "minimal",
    -- separator_style = "round",
  },

  -- telescope = { style = "bordered" },

  -- hl_override = {
  --   Comment = { italic = true },
  --   ["@comment"] = { italic = true },
  -- },
}

return M
