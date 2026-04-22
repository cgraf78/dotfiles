local M = {}

-- Theme selection:
--   NVIM_COLORSCHEME=tokyonight nvim
--   NVIM_COLORSCHEME=night-owl nvim
--   NVIM_COLORSCHEME=kanagawa nvim
--   NVIM_COLORSCHEME=oxocarbon nvim
--   NVIM_COLORSCHEME=catppuccin nvim
--   vim.g.dot_colorscheme = "gruvbox"      -- current default
--   vim.g.dot_colorscheme = "tokyonight"
--   vim.g.dot_colorscheme = "night-owl"
--   vim.g.dot_colorscheme = "kanagawa"
--   vim.g.dot_colorscheme = "oxocarbon"
--   vim.g.dot_colorscheme = "catppuccin"
M.colorscheme = vim.env.NVIM_COLORSCHEME or vim.g.dot_colorscheme or "gruvbox"

function M.apply_overrides()
  if M.colorscheme == "night-owl" then
    vim.api.nvim_set_hl(0, "CursorLine", { bg = "#0b2942" })
  end
end

function M.lazy_dir()
  return vim.fn.stdpath("data") .. "/lazy/" .. M.colorscheme .. ".nvim"
end

function M.apply()
  vim.o.termguicolors = true
  vim.cmd("silent! colorscheme " .. M.colorscheme)
  M.apply_overrides()
end

function M.lualine_theme()
  local supported = {
    gruvbox = true,
    tokyonight = true,
  }
  if supported[M.colorscheme] then
    return M.colorscheme
  end
  return "auto"
end

return M
