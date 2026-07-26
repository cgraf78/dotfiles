local M = {}

local adapter_cache = nil

local function shdeps()
  return require("config.dot-runtime").shdeps()
end

function M.module()
  if adapter_cache ~= nil then
    return adapter_cache or nil
  end

  local path = shdeps().dep_file("cgraf78/checkrun", "lib/checkrun/nvim.lua")
  if not path or vim.fn.filereadable(path) ~= 1 then
    adapter_cache = false
    return nil
  end

  adapter_cache = dofile(path)
  return adapter_cache
end

function M.capability_opts()
  local path = shdeps().dep_file("cgraf78/checkrun", "bin/checkrun")
  if path and vim.fn.executable(path) == 1 then
    -- Prefer the shdeps-managed Checkrun checkout when it is available. PATH is
    -- still the bootstrap/test fallback, but this keeps editor metadata aligned
    -- with the same Checkrun build used by shell hooks.
    return { command = { path, "capabilities", "--json" } }
  end

  return { command = { "checkrun", "capabilities", "--json" } }
end

function M.schema_opts()
  -- The Checkrun adapter can derive schema_policy.py relative to its own Lua
  -- file. Dotfiles only adds shdeps' environment so dependency-owned schema URLs
  -- resolve the same way they do under autolint.
  local env = shdeps().env()
  for _, key in ipairs({
    "SHDEPS_BIN",
    "SHDEPS_BIN_DIR",
    "SHDEPS_CONF_DIR",
    "SHDEPS_DIR",
    "SHDEPS_GIT_DEV_DIR",
    "SHDEPS_HOOKS_DIR",
    "SHDEPS_INSTALL_DIR",
    "SHDEPS_LIB",
    "SHDEPS_STATE_DIR",
  }) do
    if vim.env[key] ~= nil then
      env[key] = vim.env[key]
    end
  end
  return { env = env }
end

return M
