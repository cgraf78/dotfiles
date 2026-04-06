local map = vim.keymap.set

-- Keymaps: only active when an LSP server is attached
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local opts = { buffer = ev.buf }
    map("n", "gd", vim.lsp.buf.definition, opts)
    map("n", "gr", vim.lsp.buf.references, opts)
    map("n", "K", vim.lsp.buf.hover, opts)
    map("n", "<leader>rn", vim.lsp.buf.rename, opts)
    map("n", "<leader>ca", vim.lsp.buf.code_action, opts)
    map("n", "[d", vim.diagnostic.goto_prev, opts)
    map("n", "]d", vim.diagnostic.goto_next, opts)
  end,
})

-- nvim-cmp completion capabilities for LSP
local cmp_ok, cmp_lsp = pcall(require, "cmp_nvim_lsp")
local capabilities = cmp_ok and cmp_lsp.default_capabilities() or nil

-- C/C++
vim.lsp.config("clangd", { capabilities = capabilities })

-- Python
vim.lsp.config("pyright", { capabilities = capabilities })

-- Lua
vim.lsp.config("lua_ls", {
  capabilities = capabilities,
  settings = {
    Lua = {
      runtime = { version = "LuaJIT" },
      workspace = { library = vim.api.nvim_get_runtime_file("", true) },
    },
  },
})

-- Bash
vim.lsp.config("bashls", { capabilities = capabilities })

vim.lsp.enable({ "clangd", "pyright", "lua_ls", "bashls" })
