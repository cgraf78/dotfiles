-- Shared nvim language policy.
--
-- Checkrun owns the supported filetype registry and its Neovim filetype
-- adapter. Dotfiles owns the local policy that maps Checkrun-supported
-- filetypes onto the `sley` formatter/linter plugin names.

local M = {}

local critical_treesitter_parsers = {
  "bash",
  "c",
  "cmake",
  "cpp",
  "css",
  "dockerfile",
  "go",
  "html",
  "javascript",
  "json",
  "lua",
  "markdown",
  "markdown_inline",
  "python",
  "rust",
  "thrift",
  "toml",
  "tsx",
  "typescript",
  "yaml",
}

local empty_checkrun_capabilities = {
  version = 2,
  filetypes = {
    format = {},
    lint = {},
    custom = {
      filename = {},
      extension = {},
      patterns = {},
    },
  },
}

local checkrun_capabilities_cache = nil

local function checkrun_capabilities()
  if checkrun_capabilities_cache then
    return checkrun_capabilities_cache
  end

  local checkrun = require("config.checkrun-nvim")
  local adapter = checkrun.module()
  if adapter then
    checkrun_capabilities_cache = adapter.capabilities(checkrun.capability_opts())
  else
    checkrun_capabilities_cache = empty_checkrun_capabilities
  end

  return checkrun_capabilities_cache
end

local function sley_map(filetypes)
  local by_ft = {}
  for _, ft in ipairs(filetypes) do
    by_ft[ft] = { "sley" }
  end
  return by_ft
end

function M.sley_format_filetypes()
  local capabilities = checkrun_capabilities()
  return vim.deepcopy(capabilities.filetypes.format or {})
end

function M.checkrun_capabilities()
  return vim.deepcopy(checkrun_capabilities())
end

function M.sley_lint_filetypes()
  local capabilities = checkrun_capabilities()
  local filetypes = vim.deepcopy(capabilities.filetypes.lint or {})
  table.sort(filetypes)
  return filetypes
end

function M.sley_formatters_by_ft()
  return sley_map(M.sley_format_filetypes())
end

function M.sley_linters_by_ft()
  return sley_map(M.sley_lint_filetypes())
end

function M.critical_treesitter_parsers()
  return vim.deepcopy(critical_treesitter_parsers)
end

function M.add_filetypes()
  -- Nvim doesn't detect every basename/extension that Checkrun can route.
  -- Register the Checkrun-owned filetype projection beside the local Sley
  -- formatter/linter maps so detection and dispatch stay aligned.
  local checkrun = require("config.checkrun-nvim")
  local adapter = checkrun.module()
  if adapter then
    vim.filetype.add(adapter.filetypes(checkrun.capability_opts()))
  end
end

return M
