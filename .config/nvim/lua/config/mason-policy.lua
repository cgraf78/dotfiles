local M = {}

-- Policy:
--   * shdeps/mise/system packages are authoritative because devservers often
--     cannot use npm, pip, or Mason downloads.
--   * Mason is still useful on workstations, but only as an editor-local
--     fallback. Its bin dir is appended to PATH and every package here should
--     correspond to an enabled LSP server below, unless it is listed in
--     extra_lsp_fallback_packages with an explanation.
--   * When LazyVim language extras change, update this table and run
--     `dot doctor`; doctor compares enabled nvim-lspconfig servers against
--     these keys to catch drift.
local lsp_server_packages = {
  bashls = "bash-language-server",
  biome = "biome",
  clangd = "clangd",
  cssls = "css-lsp",
  docker_compose_language_service = "docker-compose-language-service",
  dockerls = "dockerfile-language-server",
  gopls = "gopls",
  jsonls = "json-lsp",
  lua_ls = "lua-language-server",
  marksman = "marksman",
  neocmake = "neocmakelsp",
  pyright = "pyright",
  ruff = "ruff",
  superhtml = "superhtml",
  taplo = "taplo",
  thriftls = "thriftls",
  vtsls = "vtsls",
  yamlls = "yaml-language-server",
}

local function_cmd_lsp_commands = {
  -- Some upstream nvim-lspconfig definitions use cmd functions so they can
  -- prefer project-local node_modules binaries at attach time. Disabled-Mason
  -- mode still needs the stable global executable name before startup, or it
  -- cannot tell whether a server should be skipped on restricted hosts.
  biome = "biome",
  cssls = "vscode-css-language-server",
  html = "vscode-html-language-server",
  jsonls = "vscode-json-language-server",
  yamlls = "yaml-language-server",
}

local extra_lsp_fallback_packages = {
  -- LazyVim's Rust extra disables the nvim-lspconfig `rust_analyzer` server
  -- and lets rustaceanvim start rust-analyzer directly. It still needs a
  -- Mason fallback package on non-devserver workstations.
  "rust-analyzer",
}

local function first_cmd(cmd)
  if type(cmd) == "string" then
    return cmd
  end
  if type(cmd) == "table" and type(cmd[1]) == "string" then
    return cmd[1]
  end
  return nil
end

local function config_cmd(server, config)
  local cmd = first_cmd(config and config.cmd)
  if cmd then
    return cmd
  end
  if type(config and config.cmd) == "function" then
    return function_cmd_lsp_commands[server]
  end
  return nil
end

local function extend_unique(list, items)
  local seen = {}
  for _, item in ipairs(list) do
    seen[item] = true
  end
  for _, item in ipairs(items) do
    if not seen[item] then
      table.insert(list, item)
      seen[item] = true
    end
  end
end

local function sorted_values(tbl)
  local values = {}
  for _, value in pairs(tbl) do
    table.insert(values, value)
  end
  table.sort(values)
  return values
end

local function opts_arg(first, second)
  return second or first
end

function M.lsp_server_packages()
  return vim.deepcopy(lsp_server_packages)
end

function M.lsp_fallback_packages()
  local packages = sorted_values(lsp_server_packages)
  extend_unique(packages, extra_lsp_fallback_packages)
  table.sort(packages)
  return packages
end

function M.mason_enabled()
  return vim.g.mason_disabled ~= true
end

function M.apply_mason_opts(first, second)
  local opts = opts_arg(first, second)

  -- Keep mise/shdeps/system packages authoritative. Mason is an editor-local
  -- fallback, so its bin dir should not shadow the rest of the workstation.
  opts.PATH = "append"
  opts.ensure_installed = opts.ensure_installed or {}
  extend_unique(opts.ensure_installed, M.lsp_fallback_packages())
end

function M.server_command(server, server_opts)
  local cmd = config_cmd(server, server_opts)
  if cmd then
    return cmd
  end

  -- Neovim 0.11+ stores resolved server defaults on vim.lsp.config. Check this
  -- first because LazyVim's current LSP setup reads from this table when it
  -- decides which servers to enable.
  local lsp_config = vim.lsp and vim.lsp.config
  if lsp_config then
    local ok, config = pcall(function()
      return lsp_config[server]
    end)
    cmd = ok and config_cmd(server, config) or nil
    if cmd then
      return cmd
    end
  end

  -- Keep the older nvim-lspconfig path as a fallback for configs that have not
  -- moved to vim.lsp.config yet.
  local ok, configs = pcall(require, "lspconfig.configs")
  if not ok then
    return nil
  end

  local config = configs[server]
  return config_cmd(server, config and config.default_config)
end

function M.server_available(server, server_opts)
  local cmd = M.server_command(server, server_opts)
  return cmd == nil or vim.fn.executable(cmd) == 1
end

function M.apply_lsp_policy(first, second)
  local opts = opts_arg(first, second)

  opts.setup = opts.setup or {}

  local function wrap(setup)
    return function(server, server_opts)
      -- When Mason is disabled, Neovim must not start LSP configs whose
      -- executables are absent. That is common on locked-down hosts where
      -- tools are supplied by PATH or environment overlays instead of editor
      -- installers.
      if not M.mason_enabled() and not M.server_available(server, server_opts) then
        return true
      end
      if setup then
        return setup(server, server_opts)
      end
      return nil
    end
  end

  for server, setup in pairs(opts.setup) do
    if type(setup) == "function" then
      opts.setup[server] = wrap(setup)
    end
  end
  opts.setup["*"] = wrap(opts.setup["*"])
end

return M
