return {
  {
    "iamcco/markdown-preview.nvim",
    keys = {
      {
        "<leader>am",
        "<cmd>MarkdownPreviewToggle<cr>",
        desc = "Toggle [M]arkdown Preview",
      },
    },
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    ft = { "markdown" },
    build = function()
      vim.fn["mkdp#util#install"]()
    end,
  },
}
