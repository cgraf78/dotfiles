local mason_policy = require("config.mason-policy")

-- Load after regular LSP specs so this policy can wrap the final setup table
-- instead of every language config having to remember the same Mason rules.
return {
  {
    "mason-org/mason.nvim",
    enabled = mason_policy.mason_enabled,
    opts = mason_policy.apply_mason_opts,
  },
  {
    "mason-org/mason-lspconfig.nvim",
    enabled = mason_policy.mason_enabled,
  },
  {
    "jay-babu/mason-nvim-dap.nvim",
    optional = true,
    enabled = mason_policy.mason_enabled,
  },
  {
    "neovim/nvim-lspconfig",
    opts = mason_policy.apply_lsp_policy,
  },
}
