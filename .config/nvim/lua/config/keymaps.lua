-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua

local map = vim.keymap.set

-- Exit insert/terminal mode
map("i", "kj", "<Esc>", { desc = "Exit insert mode" })
map("t", "kj", [[<C-\><C-n>]], { desc = "Exit terminal mode" })

-- Undo/redo (VSCode-style)
map({ "n", "i", "v" }, "<C-z>", "<cmd>undo<cr>", { desc = "Undo" })
map({ "n", "i", "v" }, "<C-y>", "<cmd>redo<cr>", { desc = "Redo" })

-- Select all (VSCode-style)
map("n", "<C-a>", "ggVG", { desc = "Select all" })
map("v", "<C-a>", "gg0oG$", { desc = "Select all" })
map("i", "<C-a>", "<Esc>ggVG", { desc = "Select all" })

-- Shift-arrow selection (character-wise)
map("n", "<S-Left>", "v<Left>", { desc = "Select left" })
map("n", "<S-Right>", "v<Right>", { desc = "Select right" })
map("n", "<S-Up>", "v<Up>", { desc = "Select up" })
map("n", "<S-Down>", "v<Down>", { desc = "Select down" })
map("v", "<S-Left>", "<Left>", { desc = "Extend left" })
map("v", "<S-Right>", "<Right>", { desc = "Extend right" })
map("v", "<S-Up>", "<Up>", { desc = "Extend up" })
map("v", "<S-Down>", "<Down>", { desc = "Extend down" })
map("i", "<S-Left>", "<Esc>v<Left>", { desc = "Select left" })
map("i", "<S-Right>", "<Esc>v<Right>", { desc = "Select right" })
map("i", "<S-Up>", "<Esc>v<Up>", { desc = "Select up" })
map("i", "<S-Down>", "<Esc>v<Down>", { desc = "Select down" })

-- Ctrl-arrow word navigation
map("n", "<C-Left>", "b", { desc = "Word left" })
map("n", "<C-Right>", "w", { desc = "Word right" })
map("i", "<C-Left>", "<C-o>b", { desc = "Word left" })
map("i", "<C-Right>", "<C-o>w", { desc = "Word right" })

-- Ctrl-Shift-arrow selection (word-wise)
map("n", "<C-S-Left>", "vb", { desc = "Select word left" })
map("n", "<C-S-Right>", "ve", { desc = "Select word right" })
map("v", "<C-S-Left>", "b", { desc = "Extend word left" })
map("v", "<C-S-Right>", "e", { desc = "Extend word right" })
map("i", "<C-S-Left>", "<Esc>vb", { desc = "Select word left" })
map("i", "<C-S-Right>", "<Esc>ve", { desc = "Select word right" })

-- Shift-Home/End selection
map("n", "<S-Home>", "v<Home>", { desc = "Select to line start" })
map("n", "<S-End>", "v<End>", { desc = "Select to line end" })
map("v", "<S-Home>", "<Home>", { desc = "Extend to line start" })
map("v", "<S-End>", "<End>", { desc = "Extend to line end" })
map("i", "<S-Home>", "<Esc>v<Home>", { desc = "Select to line start" })
map("i", "<S-End>", "<Esc>v<End>", { desc = "Select to line end" })

-- Shift-PageUp/Down selection
map("n", "<S-PageUp>", "v<PageUp>", { desc = "Select page up" })
map("n", "<S-PageDown>", "v<PageDown>", { desc = "Select page down" })
map("v", "<S-PageUp>", "<PageUp>", { desc = "Extend page up" })
map("v", "<S-PageDown>", "<PageDown>", { desc = "Extend page down" })
map("i", "<S-PageUp>", "<Esc>v<PageUp>", { desc = "Select page up" })
map("i", "<S-PageDown>", "<Esc>v<PageDown>", { desc = "Select page down" })

-- Arrow keys in visual mode: clear selection and move (VSCode behavior)
map("v", "<Left>", "<Esc><Left>", { desc = "Clear selection, move left" })
map("v", "<Right>", "<Esc><Right>", { desc = "Clear selection, move right" })
map("v", "<Up>", "<Esc><Up>", { desc = "Clear selection, move up" })
map("v", "<Down>", "<Esc><Down>", { desc = "Clear selection, move down" })
map("v", "<Home>", "<Esc><Home>", { desc = "Clear selection, move to line start" })
map("v", "<End>", "<Esc><End>", { desc = "Clear selection, move to line end" })
map("v", "<PageUp>", "<Esc><PageUp>", { desc = "Clear selection, page up" })
map("v", "<PageDown>", "<Esc><PageDown>", { desc = "Clear selection, page down" })
map("v", "<C-Left>", "<Esc>b", { desc = "Clear selection, word left" })
map("v", "<C-Right>", "<Esc>w", { desc = "Clear selection, word right" })
map("v", "<C-Up>", "<Esc>[m", { desc = "Clear selection, previous function" })
map("v", "<C-Down>", "<Esc>]m", { desc = "Clear selection, next function" })

-- Yank history
map("n", "<C-S-v>", "<cmd>Telescope yank_history<cr>", { desc = "Yank history" })

-- Copy/cut/paste (VSCode-style)
map("v", "<C-c>", "ygv<Esc>", { desc = "Copy selection" })
map("v", "<C-x>", "d", { desc = "Cut selection" })
map("v", "<Del>", "d", { desc = "Delete selection" })
map("v", "<BS>", "d", { desc = "Delete selection" })
map({ "n", "v" }, "<C-v>", "P", { desc = "Paste at cursor" })
map({ "n", "v" }, "p", "<Plug>(YankyPutBefore)", { desc = "Paste at cursor" })

-- WezTerm intercepts Ctrl-V and sends bracketed paste, which nvim's default
-- handler inserts AFTER the cursor. Override to insert BEFORE (VSCode behavior).
local orig_paste = vim.paste
vim.paste = function(lines, phase)
  if phase == -1 and vim.fn.mode() == "n" then
    vim.api.nvim_put(lines, "c", false, true)
    return true
  end
  return orig_paste(lines, phase)
end

-- Jump by function with Ctrl-Up/Down
map("n", "<C-Up>", "[m", { desc = "Previous function" })
map("n", "<C-Down>", "]m", { desc = "Next function" })
map("n", "<C-S-Up>", "v[m", { desc = "Select to previous function" })
map("n", "<C-S-Down>", "v]m", { desc = "Select to next function" })
map("v", "<C-S-Up>", "[m", { desc = "Extend to previous function" })
map("v", "<C-S-Down>", "]m", { desc = "Extend to next function" })

-- Join lines without cursor jump
map("n", "J", "mzJ`z", { desc = "Join lines (keep cursor)" })

-- Terminal toggle (alias for C-/)
map({ "n", "t" }, "<C-`>", function()
  Snacks.terminal()
end, { desc = "Toggle terminal" })

-- Override LazyVim's window navigation with tmux-navigator
map("n", "<C-h>", "<cmd>TmuxNavigateLeft<cr>", { desc = "Navigate left" })
map("n", "<C-j>", "<cmd>TmuxNavigateDown<cr>", { desc = "Navigate down" })
map("n", "<C-k>", "<cmd>TmuxNavigateUp<cr>", { desc = "Navigate up" })
map("n", "<C-l>", "<cmd>TmuxNavigateRight<cr>", { desc = "Navigate right" })
