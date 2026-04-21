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
      -- Set `vim.g.dotfiles_no_mason = true` in an `init` hook on a
      -- higher-priority plugin to suppress Mason installs on machines
      -- where network egress to npm/pip/go-install is blocked (e.g.
      -- corporate sandboxes) and LSP binaries are provided out-of-band.
      local ensure_installed = {}
      if not vim.g.dotfiles_no_mason then
        -- LSPs installed via mise (aqua) live on $PATH directly; Mason
        -- only handles the npm/go-install ones. See
        -- `~/.config/mise/config.toml` for lua_ls, marksman, rust_analyzer.
        ensure_installed = {
          "bashls",
          "basedpyright",
          "clangd",
          "dockerls",
          "gopls",
          "jsonls",
          "ts_ls",
          "vimls",
          "yamlls",
        }
      end

      require("mason-lspconfig").setup({
        ensure_installed = ensure_installed,
        automatic_enable = false, -- config/lsp.lua handles vim.lsp.enable
      })
    end,
  },
}
