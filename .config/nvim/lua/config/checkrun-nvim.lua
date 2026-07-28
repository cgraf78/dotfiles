local M = {}

local adapter_cache = nil
local metadata_cache = nil
local dependency_url_cache = {}

local empty_metadata = {
  version = 1,
  capabilities = {
    version = 2,
    filetypes = {
      format = {},
      lint = {},
      custom = { filename = {}, extension = {}, patterns = {} },
    },
  },
  schemas = { json = {}, yaml = {}, toml = {} },
}

local function shdeps()
  return require("config.dot-runtime").shdeps()
end

local function source_path()
  local info = debug.getinfo(1, "S")
  return ((info and info.source) or ""):gsub("^@", "")
end

local function metadata_path()
  local root = source_path():match("^(.*)/lua/config/checkrun%-nvim%.lua$")
  return root and (root .. "/checkrun-editor-metadata.json") or nil
end

local function expand_home(value)
  if type(value) ~= "string" then
    return value
  end
  local home = vim.env.HOME or os.getenv("HOME") or ""
  return value:gsub("%$HOME", (home:gsub("%%", "%%%%")))
end

local regex_magic = {
  ["\\"] = true,
  ["."] = true,
  ["^"] = true,
  ["$"] = true,
  ["*"] = true,
  ["+"] = true,
  ["?"] = true,
  ["{"] = true,
  ["}"] = true,
  ["["] = true,
  ["]"] = true,
  ["("] = true,
  [")"] = true,
  ["|"] = true,
}

local function regex_escape(value)
  local result = {}
  for index = 1, #value do
    local byte = value:sub(index, index)
    result[#result + 1] = regex_magic[byte] and ("\\" .. byte) or byte
  end
  return table.concat(result)
end

local function expand_home_regex(value)
  if type(value) ~= "string" then
    return value
  end
  local home = vim.env.HOME or os.getenv("HOME") or ""
  return value:gsub("%$HOME", (regex_escape(home):gsub("%%", "%%%%")))
end

local function materialize_url(value)
  if type(value) ~= "string" then
    return nil
  end

  local dependency, asset = value:match("^shdeps:([^/]+/[^/]+)/(.*)$")
  if dependency and asset ~= "" then
    if dependency_url_cache[value] ~= nil then
      return dependency_url_cache[value] or nil
    end
    local path = shdeps().dep_file(dependency, asset)
    if not path or vim.fn.filereadable(path) ~= 1 then
      dependency_url_cache[value] = false
      return nil
    end
    dependency_url_cache[value] = vim.uri_from_fname(path)
    return dependency_url_cache[value]
  elseif value:sub(1, 7) == "shdeps:" then
    return nil
  end

  if value == "file://$HOME" or value:sub(1, 13) == "file://$HOME/" then
    return vim.uri_from_fname(expand_home(value:sub(8)))
  end

  return expand_home(value)
end

local function materialize_patterns(patterns)
  local result = {}
  if type(patterns) ~= "table" then
    return result
  end
  for _, pattern in ipairs(patterns or {}) do
    if type(pattern) == "string" then
      result[#result + 1] = expand_home(pattern)
    end
  end
  return result
end

local function materialize_schemas(schemas)
  schemas = type(schemas) == "table" and schemas or {}
  local result = { json = {}, yaml = {}, toml = {} }
  local is_list = vim.islist or vim.tbl_islist
  local json_schemas = type(schemas.json) == "table" and is_list(schemas.json) and schemas.json
    or {}
  local yaml_schemas = type(schemas.yaml) == "table" and not is_list(schemas.yaml) and schemas.yaml
    or {}
  local toml_schemas = type(schemas.toml) == "table" and not is_list(schemas.toml) and schemas.toml
    or {}

  for _, schema in ipairs(json_schemas) do
    if type(schema) == "table" then
      local url = materialize_url(schema.url)
      if url then
        local item = vim.deepcopy(schema)
        item.url = url
        item.fileMatch = materialize_patterns(schema.fileMatch)
        result.json[#result.json + 1] = item
      end
    end
  end

  for url, patterns in pairs(yaml_schemas) do
    local materialized = materialize_url(url)
    if materialized then
      result.yaml[materialized] = materialize_patterns(patterns)
    end
  end

  for pattern, url in pairs(toml_schemas) do
    local materialized = materialize_url(url)
    if materialized then
      result.toml[expand_home_regex(pattern)] = materialized
    end
  end

  return result
end

local function editor_metadata()
  if metadata_cache then
    return metadata_cache
  end

  local path = metadata_path()
  local file = path and io.open(path, "rb") or nil
  if not file then
    metadata_cache = vim.deepcopy(empty_metadata)
    return metadata_cache
  end
  local encoded = file:read("*a")
  file:close()

  local ok, decoded = pcall(vim.json.decode, encoded)
  if not ok or type(decoded) ~= "table" or decoded.version ~= 1 then
    metadata_cache = vim.deepcopy(empty_metadata)
    return metadata_cache
  end

  metadata_cache = {
    version = 1,
    capabilities = type(decoded.capabilities) == "table" and vim.deepcopy(decoded.capabilities)
      or vim.deepcopy(empty_metadata.capabilities),
    schemas = materialize_schemas(decoded.schemas),
  }
  return metadata_cache
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
  return { capabilities = vim.deepcopy(editor_metadata().capabilities) }
end

function M.schema_opts()
  return { config = vim.deepcopy(editor_metadata().schemas) }
end

return M
