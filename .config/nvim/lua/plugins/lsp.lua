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
        -- LSPs installed via mise (aqua) live on $PATH directly; Mason only
        -- handles the npm/go-install ones. See ~/.config/mise/config.toml for
        -- lua_ls, marksman, rust_analyzer.
        ensure_installed = {
          "bashls",
          "clangd",
          "dockerls",
          "gopls",
          "jsonls",
          "pyright",
          "ts_ls",
          "vimls",
          "yamlls",
        },
        automatic_enable = false, -- config/lsp.lua handles vim.lsp.enable
      })
    end,
  },
}
