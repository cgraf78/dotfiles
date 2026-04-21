local map = vim.keymap.set

-- Global UX for hover-style info popups.
--
-- Goal: make info-on-hover (diagnostics, LSP hover, signature help) as
-- discoverable as VS Code — rounded borders, diagnostic source labels,
-- and an auto-float that pops up whenever the cursor rests on a line
-- with a diagnostic.
local float_border = "rounded"

vim.diagnostic.config({
  severity_sort = true,
  float = {
    border = float_border,
    source = true,
    header = "",
    prefix = "",
  },
  -- Inline text only for errors; warnings/info/hints still show as signs
  -- and in the cursor-hold float to keep the line visually quiet.
  virtual_text = {
    prefix = "●",
    spacing = 2,
    severity = { min = vim.diagnostic.severity.ERROR },
  },
  signs = true,
  underline = true,
  update_in_insert = false,
})

-- Cursor-hold auto-float: when the cursor sits on a diagnostic for
-- `updatetime` ms (250, set in options.lua), open a non-focused float
-- with just the diagnostics under the cursor. Skip prompt/terminal
-- buffers where a floating popup would be disruptive.
vim.api.nvim_create_autocmd("CursorHold", {
  callback = function()
    local bt = vim.bo.buftype
    if bt == "prompt" or bt == "terminal" or bt == "nofile" then
      return
    end
    vim.diagnostic.open_float(nil, { focus = false, scope = "cursor" })
  end,
})

-- Keymaps: only active when an LSP server is attached
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local b = ev.buf
    local function hover()
      vim.lsp.buf.hover({ border = float_border })
    end
    local function signature()
      vim.lsp.buf.signature_help({ border = float_border })
    end

    map("n", "gd", vim.lsp.buf.definition, { buffer = b, desc = "Go to definition" })
    map("n", "gD", vim.lsp.buf.declaration, { buffer = b, desc = "Go to declaration" })
    map("n", "gi", vim.lsp.buf.implementation, { buffer = b, desc = "Go to implementation" })
    map("n", "gr", vim.lsp.buf.references, { buffer = b, desc = "Find references" })
    map("n", "K", hover, { buffer = b, desc = "Hover docs" })
    map("n", "<C-k>", signature, { buffer = b, desc = "Signature help" })
    map("i", "<C-k>", signature, { buffer = b, desc = "Signature help" })
    map("n", "<leader>D", vim.lsp.buf.type_definition, { buffer = b, desc = "Type definition" })
    map("n", "<leader>rn", vim.lsp.buf.rename, { buffer = b, desc = "Rename symbol" })
    map("n", "<leader>ca", vim.lsp.buf.code_action, { buffer = b, desc = "Code action" })
    map("n", "[d", function()
      vim.diagnostic.jump({ count = -1 })
    end, { buffer = b, desc = "Previous diagnostic" })
    map("n", "]d", function()
      vim.diagnostic.jump({ count = 1 })
    end, { buffer = b, desc = "Next diagnostic" })
    map("n", "<leader>e", vim.diagnostic.open_float, { buffer = b, desc = "Show diagnostic" })

    -- Inlay hints: enable by default if the server supports them, and
    -- provide a quick toggle for when they get in the way.
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client and client:supports_method("textDocument/inlayHint") then
      vim.lsp.inlay_hint.enable(true, { bufnr = b })
      map("n", "<leader>ih", function()
        vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = b }), { bufnr = b })
      end, { buffer = b, desc = "Toggle inlay hints" })
    end
  end,
})

-- nvim-cmp completion capabilities for LSP
local cmp_ok, cmp_lsp = pcall(require, "cmp_nvim_lsp")
local capabilities = cmp_ok and cmp_lsp.default_capabilities() or nil

-- C/C++
--
-- Skip clangd inside a Buck-managed tree that has no `compile_commands.json`.
-- Buck supplies include paths via its own build graph, and clangd has no way
-- to resolve them without a compile DB — attaching would produce false
-- "file not found" errors on every Buck-provided header. Users who want
-- clangd coverage should generate a compile DB (e.g. `buck2 bxl
-- prelude//cxx/tools/compilation_database.bxl:generate`) and symlink it.
vim.lsp.config("clangd", {
  capabilities = capabilities,
  root_dir = function(bufnr, on_dir)
    local fname = vim.api.nvim_buf_get_name(bufnr)
    if fname == "" then
      return
    end

    local root = vim.fs.root(bufnr, {
      ".clangd",
      ".clang-tidy",
      ".clang-format",
      "compile_commands.json",
      "compile_flags.txt",
      "configure.ac",
      ".git",
    })
    if not root then
      return
    end

    if
      vim.fs.root(bufnr, { ".buckconfig" })
      and not vim.fs.root(bufnr, { "compile_commands.json" })
    then
      return
    end

    on_dir(root)
  end,
})

-- Python (basedpyright: community fork of pyright with inlay hints and
-- stricter defaults; active releases)
vim.lsp.config("basedpyright", { capabilities = capabilities })

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

-- Bash (bashls handles zsh best-effort — it understands the bash-compatible
-- subset, misses zsh-specific syntax. Paired with autolint for full coverage.)
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
      check = { command = "clippy" },
      checkOnSave = true,
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

-- Go
vim.lsp.config("gopls", { capabilities = capabilities })

-- Vimscript
vim.lsp.config("vimls", { capabilities = capabilities })

-- Dockerfile
vim.lsp.config("dockerls", { capabilities = capabilities })

-- TOML (taplo is managed by mise; binary lives on $PATH via shims)
vim.lsp.config("taplo", { capabilities = capabilities })

vim.lsp.enable({
  "bashls",
  "basedpyright",
  "clangd",
  "dockerls",
  "gopls",
  "jsonls",
  "lua_ls",
  "marksman",
  "rust_analyzer",
  "taplo",
  "ts_ls",
  "vimls",
  "yamlls",
})
