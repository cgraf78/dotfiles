local map = vim.keymap.set
local buffers = require("config.buffers")
local terminal = require("config.terminal")

-- Escape from insert mode
map("i", "kj", "<Esc>", { desc = "Exit insert mode" })
map("t", "kj", [[<C-\><C-n>]], { desc = "Exit terminal mode" })

-- Fast save
map("n", "<leader>w", ":w!<CR>", { desc = "Save file" })

-- Remap 0 to first non-blank character
map("n", "0", "^", { desc = "First non-blank char" })

-- Clear search highlight
map("n", "<leader><CR>", ":noh<CR>", { silent = true, desc = "Clear search highlight" })

-- Buffer navigation
map("n", "<leader>l", ":bnext<CR>", { desc = "Next buffer" })
map("n", "<leader>h", ":bprevious<CR>", { desc = "Previous buffer" })
map("n", "<leader>bd", function()
  buffers.delete()
end, { desc = "Delete buffer" })

-- Tab management
map("n", "<leader>tn", ":tabnew<CR>", { desc = "New tab" })
map("n", "<leader>tc", ":tabclose<CR>", { desc = "Close tab" })
map("n", "<leader>tb", function()
  terminal.open_bottom()
end, { desc = "Bottom terminal" })
map("n", "<leader>tt", function()
  terminal.open_top()
end, { desc = "Top terminal" })
map("n", "<leader>tr", function()
  terminal.open_right()
end, { desc = "Right terminal" })
map("n", "<leader>tl", function()
  terminal.open_left()
end, { desc = "Left terminal" })
map({ "n", "t" }, "<C-`>", function()
  terminal.toggle()
end, { desc = "Toggle terminal" })

-- Move lines with Alt+j/k
map("n", "<M-j>", ":m .+1<CR>==", { desc = "Move line down" })
map("n", "<M-k>", ":m .-2<CR>==", { desc = "Move line up" })
map("v", "<M-j>", ":m '>+1<CR>gv=gv", { desc = "Move selection down" })
map("v", "<M-k>", ":m '<-2<CR>gv=gv", { desc = "Move selection up" })

-- Visual mode: search for selection with * and #
map("v", "*", [[y/\V<C-R>=escape(@",'/\')<CR><CR>]], { desc = "Search selection forward" })
map("v", "#", [[y?\V<C-R>=escape(@",'/\')<CR><CR>]], { desc = "Search selection backward" })

-- Strip trailing whitespace
map("n", "<F5>", function()
  local pos = vim.api.nvim_win_get_cursor(0)
  vim.cmd([[%s/\s\+$//e]])
  vim.api.nvim_win_set_cursor(0, pos)
end, { desc = "Strip trailing whitespace" })

-- Toggle format-on-save
map("n", "<leader>tf", function()
  vim.g.disable_autoformat = not vim.g.disable_autoformat
  local state = vim.g.disable_autoformat and "disabled" or "enabled"
  vim.notify("Format-on-save " .. state)
end, { desc = "Toggle format-on-save" })

-- Center cursor after scrolling
map("n", "<C-d>", "<C-d>zz", { desc = "Scroll down (centered)" })
map("n", "<C-u>", "<C-u>zz", { desc = "Scroll up (centered)" })

-- Center cursor after search navigation
map("n", "n", "nzzzv", { desc = "Next search result (centered)" })
map("n", "N", "Nzzzv", { desc = "Prev search result (centered)" })

-- Save from any mode
map({ "n", "i", "v" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "Save file" })

-- Undo/redo
map({ "n", "i", "v" }, "<C-z>", "<cmd>undo<cr>", { desc = "Undo" })
map({ "n", "i", "v" }, "<C-y>", "<cmd>redo<cr>", { desc = "Redo" })

-- Paste over selection without losing clipboard
map("v", "<leader>p", '"_dP', { desc = "Paste without yank" })

-- Yank whole line to system clipboard
map("n", "<leader>Y", '"+yy', { desc = "Yank line to clipboard" })
map("v", "<leader>Y", '"+y', { desc = "Yank selection to clipboard" })

-- Join lines without cursor jump
map("n", "J", "mzJ`z", { desc = "Join lines (keep cursor)" })

-- Spell checking
map("n", "<leader>ss", ":setlocal spell!<CR>", { desc = "Toggle spell check" })
