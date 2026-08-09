-- Dotfiles adapter for Checkrun's provider-owned Neovim integration.
--
-- Checkrun owns the portable editor-metadata contract and all host
-- materialization rules. Dotfiles owns only two deployment choices: where its
-- checked metadata projection lives and how dependency assets resolve through
-- shdeps. Keeping those callbacks here prevents consumer policy from leaking
-- into Checkrun while avoiding a second implementation of its schema protocol.

local M = {}

local adapter_cache = nil
local metadata_cache = nil

local function dep_file(dependency, asset)
  return require("config.dot-runtime").dep_file(dependency, asset)
end

local function source_path()
  local info = debug.getinfo(1, "S")
  return ((info and info.source) or ""):gsub("^@", "")
end

local function metadata_path()
  local root = source_path():match("^(.*)/lua/config/checkrun%-nvim%.lua$")
  return root and (root .. "/checkrun-editor-metadata.json") or nil
end

function M.module()
  if adapter_cache ~= nil then
    return adapter_cache or nil
  end

  local path = dep_file("cgraf78/checkrun", "lib/checkrun/nvim.lua")
  if not path then
    adapter_cache = false
    return nil
  end

  adapter_cache = dofile(path)
  return adapter_cache
end

local function editor_metadata()
  if metadata_cache then
    return metadata_cache
  end

  local adapter = M.module()
  if not adapter then
    metadata_cache = { capabilities = {}, schemas = { json = {}, yaml = {}, toml = {} } }
    return metadata_cache
  end
  if type(adapter.editor_metadata) ~= "function" then
    error("checkrun Neovim adapter lacks editor_metadata; run dot update")
  end

  metadata_cache = adapter.editor_metadata({
    path = metadata_path(),
    resolve_dependency = dep_file,
  })
  return metadata_cache
end

function M.capability_opts()
  return { capabilities = vim.deepcopy(editor_metadata().capabilities) }
end

function M.schema_opts()
  return { config = vim.deepcopy(editor_metadata().schemas) }
end

return M
