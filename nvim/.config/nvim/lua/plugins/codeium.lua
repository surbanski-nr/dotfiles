return {
  -- :Codeium Auth
  -- :Codeium Enable
  -- :Codeium Disable
  {
    "Exafunction/codeium.vim",
    event = "VeryLazy",
    config = function()
      vim.keymap.set("i", "<M-g>", function()
        return vim.fn["codeium#Accept"]()
      end, { expr = true, silent = true })
      vim.keymap.set("i", "<M-,>", function()
        return vim.fn["codeium#CycleCompletions"](1)
      end, { expr = true, silent = true })
      vim.keymap.set("i", "<M-.>", function()
        return vim.fn["codeium#CycleCompletions"](-1)
      end, { expr = true, silent = true })
      vim.keymap.set("i", "<M-x>", function()
        return vim.fn["codeium#Clear"]()
      end, { expr = true, silent = true })

      -- -- chat seems to not be supported yet in neovim, only in vim
      -- vim.keymap.set("i", "<M-m>", function()
      --   return vim.fn["codeium#Chat"]()
      -- end, { expr = true, silent = true })

      vim.g.codeium_filetypes = {
        markdown = false,
      }
    end,
  },
}
