return {
  {
    "saghen/blink.cmp",
    version = "1.*",
    dependencies = {
      "rafamadriz/friendly-snippets",
    },
    opts = {
      keymap = {
        preset = "default",
        ["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
        ["<CR>"] = { "accept", "fallback" },
        ["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
        ["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
        ["<C-e>"] = { "cancel", "fallback" },
        ["<C-k>"] = { "show_signature", "hide_signature", "fallback" },
      },
      completion = {
        list = { selection = { preselect = true, auto_insert = false } },
        menu = {
          draw = {
            columns = {
              { "kind_icon" },
              { "label", "label_description", gap = 1 },
              { "source_name" },
            },
          },
        },
        documentation = { auto_show = true, auto_show_delay_ms = 200 },
      },
      signature = { enabled = true, window = { border = "rounded" } },
      sources = {
        default = { "lsp", "path", "snippets", "buffer" },
      },
      cmdline = {
        enabled = true,
        sources = function()
          local type = vim.fn.getcmdtype()
          if type == "/" or type == "?" then
            return { "buffer" }
          end
          return { "cmdline", "path" }
        end,
      },
    },
  },
  {
    "stevearc/conform.nvim",
    event = "BufWritePre",
    keys = {
      {
        "<leader>cf",
        function()
          require("conform").format({ async = true })
        end,
        desc = "Format buffer",
      },
    },
    config = function()
      require("conform").setup({
        formatters = {
          autoformat = {
            command = "autoformat",
            args = { "$FILENAME" },
            stdin = false,
          },
        },
        formatters_by_ft = {
          bash = { "autoformat" },
          c = { "autoformat" },
          cpp = { "autoformat" },
          css = { "autoformat" },
          javascript = { "autoformat" },
          javascriptreact = { "autoformat" },
          json = { "autoformat" },
          lua = { "autoformat" },
          markdown = { "autoformat" },
          python = { "autoformat" },
          rust = { "autoformat" },
          sh = { "autoformat" },
          toml = { "autoformat" },
          typescript = { "autoformat" },
          typescriptreact = { "autoformat" },
          yaml = { "autoformat" },
          zsh = { "autoformat" },
        },
        format_on_save = function(bufnr)
          if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
            return
          end
          if vim.g.dotfiles_lsp_format then
            return { timeout_ms = 2500, lsp_format = "prefer" }
          end
          return { timeout_ms = 2000, lsp_format = "fallback" }
        end,
      })
    end,
  },
  {
    "mfussenegger/nvim-lint",
    event = { "BufReadPost", "BufWritePost", "InsertLeave" },
    config = function()
      local lint = require("lint")

      -- Delegate every filetype to a single `autolint --json` call.
      -- The in-editor lint and the post-edit / pre-commit hooks share
      -- one codepath (the `autolint` script), so there is no way for
      -- nvim to surface a different set of diagnostics than what the
      -- commit gate enforces.
      local severity_map = {
        error = vim.diagnostic.severity.ERROR,
        warning = vim.diagnostic.severity.WARN,
        info = vim.diagnostic.severity.INFO,
        hint = vim.diagnostic.severity.HINT,
      }

      lint.linters.autolint = {
        cmd = "autolint",
        args = { "--json" },
        stdin = false,
        append_fname = true,
        stream = "stdout",
        ignore_exitcode = true,
        parser = function(output, _bufnr)
          local diags = {}
          for line in output:gmatch("[^\r\n]+") do
            local ok, d = pcall(vim.json.decode, line)
            if ok and type(d) == "table" and d.line then
              table.insert(diags, {
                lnum = math.max(0, d.line - 1),
                col = math.max(0, (d.col or 1) - 1),
                end_lnum = d.end_line and (d.end_line - 1) or nil,
                end_col = d.end_col and (d.end_col - 1) or nil,
                severity = severity_map[d.severity] or vim.diagnostic.severity.WARN,
                code = d.code,
                message = d.message,
                source = d.source or "autolint",
              })
            end
          end
          return diags
        end,
      }

      -- Every filetype `autolint` dispatches on points at the same
      -- linter; `autolint` itself decides which tool to invoke based
      -- on file extension / shebang classification.
      local autolint_fts = {
        "bash",
        "css",
        "javascript",
        "javascriptreact",
        "json",
        "jsonc",
        "lua",
        "markdown",
        "python",
        "sh",
        "toml",
        "typescript",
        "typescriptreact",
        "yaml",
        "zsh",
      }
      lint.linters_by_ft = {}
      for _, ft in ipairs(autolint_fts) do
        lint.linters_by_ft[ft] = { "autolint" }
      end

      -- Escape hatch for languages `autolint` does not yet dispatch
      -- on — wire nvim-lint's built-in per-tool linters here when the
      -- language server doesn't already surface the signal.
      --
      -- Today this map is empty. c/cpp and rust diagnostics come from
      -- the language servers (clangd with `--clang-tidy`, rust-analyzer
      -- with clippy), which already parse the TU / crate and stream
      -- results over LSP — duplicating that via nvim-lint means a
      -- second process, a second compdb lookup, and worse UX when the
      -- tool is missing. Let the LSP own static-analyzer signals.
      --
      -- Migration path: once `autolint` gains a `case "$ext"` branch
      -- for a new language, append the ft to `autolint_fts` above.
      -- If a language needs a lint signal that no LSP produces and
      -- `autolint` doesn't cover, add it here as
      --   <ft> = { "<nvim-lint-linter-name>" }.
      local extra_linters_by_ft = {}
      for ft, linters in pairs(extra_linters_by_ft) do
        lint.linters_by_ft[ft] = linters
      end

      vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "InsertLeave" }, {
        callback = function()
          lint.try_lint()
        end,
      })
    end,
  },
  {
    "numToStr/Comment.nvim",
    event = "BufReadPost",
    config = function()
      require("Comment").setup()
    end,
  },
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = function()
      require("nvim-autopairs").setup()
    end,
  },
  { "tpope/vim-surround" },
}
