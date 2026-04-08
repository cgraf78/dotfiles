return {
  { "neovim/nvim-lspconfig", lazy = true },
  { "b0o/schemastore.nvim", lazy = true },
  {
    "williamboman/mason.nvim",
    build = ":MasonUpdate",
    config = function()
      require("mason").setup()
    end,
  },
  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = { "williamboman/mason.nvim", "neovim/nvim-lspconfig" },
    config = function()
      require("mason-lspconfig").setup({
        ensure_installed = {
          "bashls",
          "clangd",
          "jsonls",
          "lua_ls",
          "marksman",
          "pyright",
          "rust_analyzer",
          "ts_ls",
          "yamlls",
        },
        automatic_enable = false, -- config/lsp.lua handles vim.lsp.enable
      })
    end,
  },
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = { "williamboman/mason.nvim" },
    config = function()
      require("mason-tool-installer").setup({
        ensure_installed = {
          "eslint_d",
          "prettier",
          "ruff",
          "shfmt",
          "stylua",
          "taplo",
        },
      })
    end,
  },
}
