return {
  -- Loaded with empty sources because overlay plugins depend on null-ls modules
  -- at init time. Empty sources keeps it inert (conform + nvim-lint handle formatting).
  { "nvimtools/none-ls.nvim", opts = { sources = {} } },

  {
    "saghen/blink.cmp",
    opts = {
      keymap = {
        ["<Tab>"] = { "select_and_accept", "snippet_forward", "fallback" },
      },
    },
  },
}
