-- `sley hook lint-file --json` is the one-file lint path shared by editor and
-- hook integrations. The JSON flag is passed through to the underlying tool so
-- environment-specific overrides can decide how to satisfy editor diagnostics.
local sley_nvim = require("config.sley-nvim").module()

return {
  {
    "mfussenegger/nvim-lint",
    opts = {
      -- The configured linters read saved files, so InsertLeave repeats stale work.
      events = { "BufReadPost", "BufWritePost" },
      linters = {
        sley = sley_nvim.nvim_lint_linter({
          condition = function()
            return not vim.b.autolint_disabled
          end,
        }),
      },
      linters_by_ft = require("config.language-policy").sley_linters_by_ft(),
    },
  },
}
