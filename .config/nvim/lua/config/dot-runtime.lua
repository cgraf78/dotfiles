local M = {}

local shdeps_cache = nil

local function source_path()
  local info = debug.getinfo(1, "S")
  local source = info and info.source or ""
  return source:gsub("^@", "")
end

local function dot_home()
  local home = source_path():match("^(.*)/%.config/nvim/lua/config/dot%-runtime%.lua$")
  if home and home ~= "" then
    return home
  end
  return vim.env.HOME or os.getenv("HOME") or ""
end

function M.shdeps()
  if not shdeps_cache then
    -- Tests and plugin code may temporarily point HOME at fixture trees. The
    -- loader itself is shipped by dotfiles, so load it relative to this module
    -- rather than the current process environment; dependency resolution then
    -- delegates to shdeps' public Lua API.
    local home = dot_home()
    shdeps_cache = dofile(home .. "/.local/lib/dot/lua/shdeps-loader.lua").new({ home = home })
  end
  return shdeps_cache
end

-- Resolve a shdeps-managed dependency file and load it via dofile. Errors when
-- the file is missing unless opts.optional is set, in which case it returns nil
-- so adapters that degrade gracefully can fall back to other behavior.
function M.load_dep(repo, relpath, opts)
  opts = opts or {}
  local path = M.shdeps().dep_file(repo, relpath)
  if not path or vim.fn.filereadable(path) ~= 1 then
    if opts.optional then
      return nil
    end
    error(repo .. "/" .. relpath .. " not found through shdeps")
  end
  return dofile(path)
end

return M
