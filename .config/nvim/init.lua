-- ==========================================================================
--  Neovim config — migrated from amix/vimrc
--  Keeps: leader=comma, kj escape, 2-space tabs, key mappings you use
--  Drops: Windows/GUI compat, CoffeeScript/Mako/Twig, unused plugins
-- ==========================================================================

require("config.options")
require("config.keymaps")
require("config.autocmds")

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup("plugins", require("config.lazy"))

require("config.lsp")

-- BigGrep (loaded after plugins so Telescope is available)
if vim.fn.executable("xbgs") == 1 then
  require("config.biggrep")
end
