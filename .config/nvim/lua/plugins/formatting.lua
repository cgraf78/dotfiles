-- `sley hook format-file` is the one-file formatting path shared by editor,
-- agent, Git, and Sapling hooks. The broader `sley fix` command is intentionally
-- not used on save because it operates on a repo change scope, not one buffer.
local sley_nvim = require("config.sley-nvim").module()

return {
  {
    "stevearc/conform.nvim",
    opts = {
      formatters = {
        sley = sley_nvim.conform_formatter(),
      },
      formatters_by_ft = require("config.language-policy").sley_formatters_by_ft(),
    },
  },
}
