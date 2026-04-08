local map = vim.keymap.set

-- Keymaps: only active when an LSP server is attached
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local opts = { buffer = ev.buf }
    map("n", "gd", vim.lsp.buf.definition, opts)
    map("n", "gD", vim.lsp.buf.declaration, opts)
    map("n", "gi", vim.lsp.buf.implementation, opts)
    map("n", "gr", vim.lsp.buf.references, opts)
    map("n", "K", vim.lsp.buf.hover, opts)
    map("n", "<C-k>", vim.lsp.buf.signature_help, opts)
    map("n", "<leader>D", vim.lsp.buf.type_definition, opts)
    map("n", "<leader>rn", vim.lsp.buf.rename, opts)
    map("n", "<leader>ca", vim.lsp.buf.code_action, opts)
    map("n", "[d", vim.diagnostic.goto_prev, opts)
    map("n", "]d", vim.diagnostic.goto_next, opts)
    map("n", "<leader>e", vim.diagnostic.open_float, opts)
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
vim.lsp.config("bashls", {
  capabilities = capabilities,
  filetypes = { "sh", "bash", "zsh" },
})

-- TypeScript/JavaScript
vim.lsp.config("ts_ls", { capabilities = capabilities })

-- Rust
vim.lsp.config("rust_analyzer", {
  capabilities = capabilities,
  settings = {
    ["rust-analyzer"] = {
      inlayHints = {
        parameterHints = { enable = true },
        typeHints = { enable = true },
        chainingHints = { enable = true },
      },
      checkOnSave = { command = "clippy" },
    },
  },
})

-- JSON (with schemastore for config file validation)
local schemastore_ok, schemastore = pcall(require, "schemastore")
vim.lsp.config("jsonls", {
  capabilities = capabilities,
  settings = {
    json = {
      schemas = schemastore_ok and schemastore.json.schemas() or {},
      validate = { enable = true },
    },
  },
})

-- YAML (with schemastore for config file validation)
vim.lsp.config("yamlls", {
  capabilities = capabilities,
  settings = {
    yaml = {
      schemas = schemastore_ok and schemastore.yaml.schemas() or {},
      validate = true,
    },
  },
})

-- Markdown
vim.lsp.config("marksman", { capabilities = capabilities })

vim.lsp.enable({
  "bashls",
  "clangd",
  "jsonls",
  "lua_ls",
  "marksman",
  "pyright",
  "rust_analyzer",
  "ts_ls",
  "yamlls",
})
