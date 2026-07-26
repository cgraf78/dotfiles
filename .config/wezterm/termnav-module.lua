local function readable(path)
  if not path or path == "" then
    return false
  end
  local file = io.open(path, "r")
  if file then
    file:close()
    return true
  end
  return false
end

local function source_dir()
  -- selene: allow(global_usage)
  local config_dir = rawget(_G, "dotfiles_wezterm_config_dir")
  if type(config_dir) == "string" and config_dir ~= "" then
    return (config_dir:gsub("\\", "/"))
  end

  if type(debug) == "table" and type(debug.getinfo) == "function" then
    local info = debug.getinfo(1, "S")
    local source = (info and info.source or ""):gsub("^@", ""):gsub("\\", "/")
    return source:match("^(.*)/[^/]+$")
  end

  return "."
end

local function dot_home()
  local source = (source_dir() or "") .. "/termnav-module.lua"
  return source:match("^(.*)/%.config/wezterm/termnav%-module%.lua$") or os.getenv("HOME") or ""
end

local M = {}

function M.load(copied_name, relative_path)
  local dir = source_dir()
  local copied = dir and (dir .. "/" .. copied_name)
  if readable(copied) then
    return dofile(copied)
  end

  local home = dot_home()
  local shdeps = dofile(home .. "/.local/lib/dot/lua/shdeps-loader.lua").new({ home = home })
  local module_path = shdeps.dep_file("cgraf78/termnav", relative_path)
  if not module_path then
    error("termnav module not found through shdeps: " .. relative_path)
  end

  return dofile(module_path)
end

return M
