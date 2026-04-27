-- `autoformat` is a wrapper script that delegates to the right formatter per
-- environment (e.g. prettier/stylua at home, different tools at work). This
-- lets the same nvim config work across personal and work machines.
return {
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
    },
  },
}
