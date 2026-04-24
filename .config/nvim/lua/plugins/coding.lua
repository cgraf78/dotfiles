local autoformat_fts = {
  "bash",
  "c",
  "cpp",
  "css",
  "javascript",
  "javascriptreact",
  "json",
  "lua",
  "markdown",
  "python",
  "rust",
  "sh",
  "toml",
  "typescript",
  "typescriptreact",
  "yaml",
  "zsh",
}

local severity_map = {
  error = vim.diagnostic.severity.ERROR,
  warning = vim.diagnostic.severity.WARN,
  info = vim.diagnostic.severity.INFO,
  hint = vim.diagnostic.severity.HINT,
}

return {
  { "zbirenbaum/copilot.lua", enabled = false },
  { "fang2hou/blink-copilot", enabled = false },

  {
    "stevearc/conform.nvim",
    opts = {
      formatters = {
        autoformat = {
          command = "autoformat",
          args = { "$FILENAME" },
          stdin = false,
        },
      },
      formatters_by_ft = (function()
        local t = {}
        for _, ft in ipairs(autoformat_fts) do
          t[ft] = { "autoformat" }
        end
        return t
      end)(),
      format_on_save = function(bufnr)
        return vim.b[bufnr].format_on_save_opts or { timeout_ms = 2000, lsp_format = "fallback" }
      end,
    },
  },

  {
    "mfussenegger/nvim-lint",
    opts = function(_, opts)
      local lint = require("lint")

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

      vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "InsertLeave" }, {
        callback = function(args)
          if vim.b[args.buf].autolint_disabled then
            return
          end
          lint.try_lint({ "autolint" })
        end,
      })
    end,
  },
}
