return {
  -- Cutlass overrides the delete operations to actually just delete and not affect the current yank.
  {
    "gbprod/cutlass.nvim",
    event = "BufReadPost",
    opts = {
      cut_key = "x",
      override_del = true,
    },
  },
}
