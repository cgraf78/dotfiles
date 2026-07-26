local function source_dir()
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

return dofile(source_dir() .. "/termnav-module.lua").load(
  "termnav-link-routes.lua",
  "lib/termnav/wezterm/link-routes.lua"
)
