local M = {}

local shell_glob = "*@(.sh|.inc|.bash|.zsh|.command)"
local shell_filetypes = { "bash", "sh", "zsh" }
local vcs_markers = { ".git", ".hg", ".jj", ".svn" }
local vcs_root_env = {
  -- The PATH-visible git launcher treats HOME as the bare dotfiles repo. Root
  -- probes need real Git semantics unless they explicitly opt into the bare
  -- dotfiles worktree below.
  DOT_GIT_REAL = "1",
  SLEY_SKIP_BARE_REPO_FALLBACK = "1",
}
local dotfiles_tracked_cache = nil

local home_files = {
  ".bashrc",
  ".bash_profile",
  ".profile",
  ".zshenv",
  ".zprofile",
  ".zshrc",
}

-- HOME shell indexing must stay aligned with the VS Code HOME workspace
-- policy in ~/.vscode/settings.json. The shdeps bin glob indexes installed
-- targets instead of the ~/.local/bin symlink facade, while .local/bin stays a
-- direct-open path below.
local home_globs = {
  ".local/share/cgraf78/*/bin/*",
}

local home_dirs = {
  {
    prefix = ".config/dot/merge-hooks.d/",
    glob = ".config/dot/merge-hooks.d/**/" .. shell_glob,
  },
  {
    prefix = ".config/shdeps/hooks.d/",
    glob = ".config/shdeps/hooks.d/**/" .. shell_glob,
  },
  {
    prefix = ".config/shell/",
    glob = ".config/shell/**/" .. shell_glob,
  },
  {
    prefix = ".local/lib/dotfiles/legacy-dot/",
    glob = ".local/lib/dotfiles/legacy-dot/**/" .. shell_glob,
  },
  {
    prefix = ".local/share/cgraf78/",
    glob = ".local/share/cgraf78/**/" .. shell_glob,
  },
  {
    prefix = ".local/bin/",
    direct = true,
  },
}

local function strip_trailing_slash(path)
  if path == "/" then
    return path
  end
  return (path:gsub("/+$", ""))
end

local function home()
  return strip_trailing_slash(vim.fn.fnamemodify(vim.env.HOME or "~", ":p"))
end

local function dotfiles_git_dir()
  return home() .. "/.dotfiles"
end

local function normalize_dir(path)
  return strip_trailing_slash(vim.fn.fnamemodify(path, ":p"))
end

local function read_first_line(path)
  local ok, lines = pcall(vim.fn.readfile, path, "", 1)
  if not ok then
    return nil
  end
  return lines[1]
end

-- persistence.nvim asks for the branch once per primary and alias session
-- save. Reading Git's symbolic HEAD preserves its branch-session naming while
-- avoiding a PATH launcher process for every root in the save batch.
function M.persistence_branch(cwd)
  local root = normalize_dir(cwd or vim.fn.getcwd())
  local marker = root .. "/.git"
  local marker_stat = vim.uv.fs_stat(marker)
  if not marker_stat then
    return nil
  end

  local git_dir = marker
  if marker_stat.type == "file" then
    local target = (read_first_line(marker) or ""):match("^gitdir:%s*(.-)%s*$")
    if not target or target == "" then
      return nil
    end
    if not target:match("^/") then
      target = vim.fs.dirname(marker) .. "/" .. target
    end
    git_dir = normalize_dir(target)
  elseif marker_stat.type ~= "directory" then
    return nil
  end

  local head = read_first_line(git_dir .. "/HEAD")
  return head and head:match("^ref:%s*refs/heads/(.-)%s*$") or nil
end

local function contains(root, path)
  root = normalize_dir(root)
  path = normalize_dir(path)
  return path == root or path:sub(1, #root + 1) == root .. "/"
end

local function marker_root(cwd)
  local marker = vim.fs.find(vcs_markers, { path = cwd, upward = true, limit = 1 })[1]
  if marker then
    local root = normalize_dir(vim.fs.dirname(marker))
    if root ~= home() then
      return root
    end
  end
  return nil
end

local function option_marker_root(opts)
  if type(opts) == "table" and type(opts.marker_root) == "string" and opts.marker_root ~= "" then
    local root = normalize_dir(opts.marker_root)
    if root ~= home() then
      return root
    end
  end
  return nil
end

local function dotfiles_index_identity(git_dir)
  if vim.env.GIT_INDEX_FILE and vim.env.GIT_INDEX_FILE ~= "" then
    return nil
  end

  local stat = vim.uv.fs_stat(git_dir .. "/index")
  if not stat or stat.type ~= "file" or not stat.mtime or not stat.ctime then
    return nil
  end

  local fields = {
    stat.dev,
    stat.ino,
    stat.size,
    stat.mtime.sec,
    stat.mtime.nsec,
    stat.ctime.sec,
    stat.ctime.nsec,
  }
  for _, field in ipairs(fields) do
    if field == nil then
      return nil
    end
  end
  return table.concat(fields, ":")
end

local function dotfiles_tracked_root(cwd)
  local root = home()
  if not contains(root, cwd) then
    return nil
  end

  local git_dir = dotfiles_git_dir()
  local stat = vim.uv.fs_stat(git_dir)
  if not stat or stat.type ~= "directory" then
    return nil
  end

  local normalized = normalize_dir(cwd)
  if normalized == root then
    return root
  end

  local rel = normalized:sub(#root + 2)
  local cwd_stat = vim.uv.fs_stat(normalized)
  local index_identity = dotfiles_index_identity(git_dir)
  local cache_key = index_identity
      and table.concat(
        { normalized, cwd_stat and cwd_stat.type or "missing", index_identity },
        "\0"
      )
    or nil
  if cache_key and dotfiles_tracked_cache and dotfiles_tracked_cache.key == cache_key then
    return dotfiles_tracked_cache.root or nil
  end

  local args = {
    "git",
    "-C",
    root,
    "--git-dir",
    git_dir,
    "--work-tree",
    root,
    "ls-files",
    "--",
    rel,
  }
  if cwd_stat and cwd_stat.type == "directory" then
    args[#args + 1] = rel .. "/**"
  end

  local tracked = vim.fn.system(args)
  if vim.v.shell_error ~= 0 then
    return nil
  end

  local tracked_root = tracked ~= "" and root or false
  -- Workspace pickers commonly ask about the same path several times in one
  -- interaction. Keep only that result in memory, and bind it to the complete
  -- bare-index identity so staging or atomic index replacement invalidates it.
  if cache_key then
    dotfiles_tracked_cache = { key = cache_key, root = tracked_root }
  end
  return tracked_root or nil
end

local function sley_root(cwd, env, opts)
  local fast_root = option_marker_root(opts) or marker_root(cwd)
  if fast_root then
    return fast_root
  end

  -- HOME contains many non-project directories. Falling through to `sley status`
  -- there made opening ordinary dotfiles wait on a repo-wide probe; the bare
  -- dotfiles case is handled above with a cheap tracked-path query.
  if contains(home(), cwd) then
    return nil
  end

  if vim.fn.executable("sley") ~= 1 then
    return nil
  end

  local ok_system, result = pcall(function()
    return vim
      .system({ "sley", "status", "--json" }, {
        cwd = cwd,
        text = true,
        env = env,
      })
      :wait()
  end)
  if not ok_system or result.code ~= 0 or result.stdout == "" then
    return nil
  end

  local ok_json, decoded = pcall(vim.json.decode, result.stdout)
  if ok_json and type(decoded) == "table" and type(decoded.root) == "string" then
    return decoded.root
  end
  return nil
end

local function dotfiles_root(cwd)
  return dotfiles_tracked_root(cwd)
end

local function dotfiles_lazygit_opts(path, ctx)
  local rel = ctx.relative_to_default_root(path)
  if not rel then
    return nil
  end

  local root = ctx.default_root
  local git_dir = dotfiles_git_dir()
  local stat = vim.uv.fs_stat(git_dir)
  if not stat or stat.type ~= "directory" then
    return nil
  end

  vim.fn.system({
    "git",
    "--git-dir",
    git_dir,
    "--work-tree",
    root,
    "ls-files",
    "--error-unmatch",
    "--",
    rel,
  })
  if vim.v.shell_error ~= 0 then
    return nil
  end

  return {
    cwd = root,
    args = {
      "--work-tree",
      root,
      "--git-dir",
      git_dir,
    },
  }
end

function M.options()
  return {
    large_root_detector = function(root, opts)
      return _G.in_large_repo(root, opts)
    end,
    workspace = {
      ignored_marker_roots = { home() },
      repo_root_detector = function(cwd, opts)
        return sley_root(cwd, vcs_root_env, opts)
      end,
      home_workspace_detector = function(cwd)
        return dotfiles_root(cwd)
      end,
    },
    lazygit = {
      opts_for_path = dotfiles_lazygit_opts,
    },
    session = {
      save_debounce_ms = 500,
    },
    shell = {
      shell_glob = shell_glob,
      file_globs = { "*.sh", "*.inc", "*.bash", "*.zsh", "*.command" },
      home_files = home_files,
      home_globs = home_globs,
      home_dirs = home_dirs,
      overlay = {
        enabled = true,
        root_prefix = ".dotfiles-",
        home_dir = "home",
      },
    },
    navigation = {
      path_first_filetypes = shell_filetypes,
      shell_filetypes = shell_filetypes,
      shell_module = "nvim_workspace.shell",
      prefer_shell_for_home_paths = true,
    },
  }
end

return M
