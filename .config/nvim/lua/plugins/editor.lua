return {
  -- Disable snacks features that conflict with terminal rendering or feel laggy
  -- over SSH (smooth scroll, animations, startup dashboard).
  {
    "folke/snacks.nvim",
    opts = {
      dashboard = { enabled = false },
      scroll = { enabled = false },
      animate = { enabled = false },
    },
  },

  {
    "mbbill/undotree",
    keys = {
      { "<leader>u", "<cmd>UndotreeToggle<cr>", desc = "Toggle undo tree" },
    },
  },
}
