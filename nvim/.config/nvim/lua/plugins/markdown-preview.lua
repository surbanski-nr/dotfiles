return {
  {
    "iamcco/markdown-preview.nvim",
    keys = {
      {
        "<leader>mp",
        "<cmd>MarkdownPreviewToggle<cr>",
        desc = "Markdown Preview Toggle",
      },
    },
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    ft = { "markdown" },
    build = function()
      vim.fn["mkdp#util#install"]()
    end,
  },
}
