local M = {}

local adapter_cache = nil

function M.module()
  if adapter_cache ~= nil then
    return adapter_cache
  end

  local shdeps = require("config.dot-runtime").shdeps()
  local path = shdeps.dep_file("cgraf78/sley", "lib/sley/nvim.lua")
  if not path or vim.fn.filereadable(path) ~= 1 then
    error("sley nvim adapter module not found through shdeps")
  end

  adapter_cache = dofile(path)
  return adapter_cache
end

return M
