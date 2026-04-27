-- `autolint` is a wrapper script (like autoformat) that delegates to the right
-- linter per environment. Emits one JSON object per line for the custom parser.
return {
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters = {
        autolint = {
          cmd = "autolint",
          args = { "--json" },
          stdin = false,
          append_fname = true,
          stream = "stdout",
          ignore_exitcode = true,
          parser = function(output, _bufnr)
            local severity_map = {
              error = vim.diagnostic.severity.ERROR,
              warning = vim.diagnostic.severity.WARN,
              info = vim.diagnostic.severity.INFO,
              hint = vim.diagnostic.severity.HINT,
            }
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
        },
      },
      linters_by_ft = {
        bash = { "autolint" },
        css = { "autolint" },
        javascript = { "autolint" },
        javascriptreact = { "autolint" },
        json = { "autolint" },
        jsonc = { "autolint" },
        lua = { "autolint" },
        markdown = { "autolint" },
        python = { "autolint" },
        sh = { "autolint" },
        toml = { "autolint" },
        typescript = { "autolint" },
        typescriptreact = { "autolint" },
        yaml = { "autolint" },
        zsh = { "autolint" },
      },
    },
  },
}
