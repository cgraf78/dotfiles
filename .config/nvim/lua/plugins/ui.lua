return {
  -- Overlay configs can set vim.g.disable_bufferline to hide the tab bar.
  {
    "akinsho/bufferline.nvim",
    enabled = not vim.g.disable_bufferline,
  },

  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = "markdown",
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
    opts = {},
  },

  {
    "HiPhish/rainbow-delimiters.nvim",
    event = "BufReadPost",
  },
}
