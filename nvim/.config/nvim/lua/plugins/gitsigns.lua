return {
  "lewis6991/gitsigns.nvim",
  opts = {
    on_attach = function(bufnr)
      local gs = package.loaded.gitsigns

      local function opts(desc)
        return { buffer = bufnr, desc = desc }
      end

      local map = vim.keymap.set

      map("n", "]c", function()
        if vim.wo.diff then
          vim.cmd.normal { "]c", bang = true }
        else
          gs.nav_hunk "next"
        end
      end, opts "Next Hunk")

      map("n", "[c", function()
        if vim.wo.diff then
          vim.cmd.normal { "[c", bang = true }
        else
          gs.nav_hunk "prev"
        end
      end, opts "Prev Hunk")

      map("n", "<leader>gr", gs.reset_hunk, opts "Reset Hunk")
      map("n", "<leader>gp", gs.preview_hunk, opts "Preview Hunk")
      map("n", "<leader>gb", gs.blame_line, opts "Blame Line")
    end,
  },
}

-- return {
--   require("gitsigns").setup {
--     on_attach = function(bufnr)
--       local gitsigns = require "gitsigns"
--       local function opts(desc)
--         return { buffer = bufnr, desc = desc }
--       end
--
--       local map = vim.keymap.set
--
--       map("n", "]c", function()
--         if vim.wo.diff then
--           vim.cmd.normal { "]c", bang = true }
--         else
--           gitsigns.nav_hunk "next"
--         end
--       end)
--
--       map("n", "[c", function()
--         if vim.wo.diff then
--           vim.cmd.normal { "[c", bang = true }
--         else
--           gitsigns.nav_hunk "prev"
--         end
--       end)
--
--       map("n", "<leader>gR", gitsigns.reset_hunk, opts "Reset Hunk")
--       map("n", "<leader>gs", gitsigns.stage_buffer, opts "Stage Buffer")
--       map("n", "<leader>gB", gitsigns.reset_buffer, opts "Reset Buffer")
--       map("n", "<leader>gp", gitsigns.preview_hunk, opts "Preview Hunk")
--       map("n", "<leader>gb", function()
--         gitsigns.blame_line { full = true }
--       end, opts "Blame Line")
--       map("n", "<leader>gf", gitsigns.diffthis, opts "Diff This")
--       map("n", "<leader>gF", function()
--         gitsigns.diffthis "~"
--       end, opts "Diff This ~")
--       map("n", "<leader>gd", gitsigns.toggle_deleted, opts "Toggle Deleted")
--     end,
--   },
-- }
