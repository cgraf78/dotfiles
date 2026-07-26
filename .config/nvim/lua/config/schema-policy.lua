local M = {}

local function checkrun()
  return require("config.checkrun-nvim")
end

local function adapter()
  return checkrun().module()
end

function M.json_schemas()
  local mod = adapter()
  return mod and mod.json_schemas(checkrun().schema_opts()) or {}
end

function M.yaml_schemas()
  local mod = adapter()
  return mod and mod.yaml_schemas(checkrun().schema_opts()) or {}
end

function M.yaml_before_init(_, new_config)
  local mod = adapter()
  if not mod then
    return
  end
  return mod.yaml_before_init(checkrun().schema_opts())(_, new_config)
end

function M.toml_schema_associations()
  local mod = adapter()
  return mod and mod.toml_schema_associations(checkrun().schema_opts()) or {}
end

return M
