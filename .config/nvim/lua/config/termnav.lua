local termnav =
  require("config.dot-runtime").load_dep("cgraf78/termnav", "lib/termnav/nvim/setup.lua")

local M = {}

function M.setup(options)
  options = options or {}
  -- Dotfiles owns local policy, including augroup naming. The termnav module owns
  -- the WezTerm user-var protocol and publish/clear lifecycle.
  options.group_name = options.group_name or "dot_termnav"
  return termnav.setup(options)
end

return M
