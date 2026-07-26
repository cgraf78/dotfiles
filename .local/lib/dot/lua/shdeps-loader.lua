local M = {}

local function readable(path)
  if type(path) ~= "string" or path == "" then
    return false
  end

  local file = io.open(path, "r")
  if not file then
    return false
  end
  file:close()
  return true
end

local function dirname(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  return path:match("^(.*)/[^/]+$")
end

local function add_candidate(candidates, root)
  if type(root) == "string" and root ~= "" then
    table.insert(candidates, root .. "/lua/shdeps/bootstrap.lua")
  end
end

local function paths(home)
  local candidates = {}

  local lib = os.getenv("SHDEPS_LIB")
  if type(lib) == "string" and lib ~= "" then
    add_candidate(candidates, dirname(lib))
  end

  local git_dev_dir = os.getenv("SHDEPS_GIT_DEV_DIR")
  if type(git_dev_dir) ~= "string" or git_dev_dir == "" then
    git_dev_dir = type(home) == "string" and (home .. "/git") or nil
  end
  add_candidate(candidates, git_dev_dir and (git_dev_dir .. "/shdeps"))

  add_candidate(candidates, os.getenv("SHDEPS_DIR"))
  add_candidate(candidates, type(home) == "string" and (home .. "/.local/share/shdeps") or nil)

  local env_home = os.getenv("HOME")
  add_candidate(
    candidates,
    type(env_home) == "string" and (env_home .. "/.local/share/shdeps") or nil
  )

  return candidates
end

function M.load(options)
  options = options or {}
  local home = options.home

  -- Dotfiles only owns seed discovery. shdeps' bootstrap module owns the
  -- reusable source/release lookup policy and returns the public Lua API.
  for _, path in ipairs(paths(home)) do
    if readable(path) then
      return dofile(path).load(options)
    end
  end

  error("shdeps Lua bootstrap API not found; expected lua/shdeps/bootstrap.lua under shdeps root")
end

function M.new(options)
  return M.load(options).new(options)
end

return M
