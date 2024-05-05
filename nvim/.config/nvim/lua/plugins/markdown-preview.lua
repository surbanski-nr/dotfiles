return {
  {
    "iamcco/markdown-preview.nvim",
    keys = {
      {
        "<leader>ap",
        "<cmd>MarkdownPreviewToggle<cr>",
        desc = "Toggle Markdown [P]review",
      },
    },
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    ft = { "markdown" },
    build = function()
      vim.fn["mkdp#util#install"]()
    end,
  },
}
