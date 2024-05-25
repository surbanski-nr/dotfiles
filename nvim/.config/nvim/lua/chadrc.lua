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
  },

  nvdash = {
    load_on_startup = true,

    header = {
      "                                                     ",
      "  ███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗ ",
      "  ████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║ ",
      "  ██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║ ",
      "  ██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║ ",
      "  ██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║ ",
      "  ╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝ ",
      "                                                     ",
    },

    buttons = {
      { "  Find File", "Spc f f", "Telescope find_files" },
      { "󰈚  Recent Files", "Spc f o", "Telescope oldfiles" },
      { "󰈭  Find Word", "Spc f w", "Telescope live_grep" },
      { "  Projects", "Spc f p", "Telescope projects" },
      { "  Lazy", "Spc a l", "Lazy" },
    },
  },

  gl_add = {
    WinBar = { link = "Normal" },
    WinBarNC = { link = "Normal" },
    LspInlayHint = { link = "Comment" },
  },

  hl_override = {
    Comment = {
      italic = true,
    },
    ["@comment"] = { italic = true },
    DiffAdd = { bg = "NONE", fg = "#bada9f" },
    -- DiffChange = { fg = "#e5d5ac", bold = true },
    DiffDelete = { bg = "NONE", fg = "#ffb0b0" },
    DiffText = { fg = "orange", bold = true },
    WildMenu = { fg = "black" },
    -- Search = { fg = "black", bg = "blue" },
    -- CurSearch = { fg = "black", bg = "blue" },
    -- IncSearch = { fg = "black", bg = "red" },
    NvDashAscii = { bg = "NONE", fg = "orange" },
    NvDashButtons = { bg = "NONE" },
    FoldColumn = { bg = "NONE" },
    TblineFill = { link = "Normal" },
    NvimTreeRootFolder = { link = "NvimTreeFolderName" },
    ["@keyword.exception"] = {
      link = "Conditional",
    },
  },
}

return M
