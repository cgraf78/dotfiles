-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua

-- Vim's default "inclusive" selection includes the character under the cursor,
-- causing off-by-one vs VSCode's between-characters model.
vim.o.selection = "exclusive"
-- LazyVim sets clipboard="" over SSH, breaking Ctrl-C copy to OS clipboard.
-- Force unnamedplus so yanks reach the system clipboard via OSC 52.
vim.o.clipboard = "unnamedplus"

vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.swapfile = false

-- Set vim.g.mason_disabled = true in environments where network
-- egress to npm/pip/go-install is blocked and LSP binaries are
-- provided out-of-band.

--- Override in a work overlay to detect large repos where recursive
--- filesystem traversal is prohibitively expensive. Checks the
--- current buffer's file path, not cwd.
function _G.in_large_repo()
  return false
end
