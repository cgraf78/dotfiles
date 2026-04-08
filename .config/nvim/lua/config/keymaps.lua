local map = vim.keymap.set

-- Escape from insert mode
map("i", "kj", "<Esc>", { desc = "Exit insert mode" })

-- Fast save
map("n", "<leader>w", ":w!<CR>", { desc = "Save file" })

-- Remap 0 to first non-blank character
map("n", "0", "^", { desc = "First non-blank char" })

-- Clear search highlight
map("n", "<leader><CR>", ":noh<CR>", { silent = true, desc = "Clear search highlight" })

-- Buffer navigation
map("n", "<leader>l", ":bnext<CR>", { desc = "Next buffer" })
map("n", "<leader>h", ":bprevious<CR>", { desc = "Previous buffer" })
map("n", "<leader>bd", ":bdelete<CR>", { desc = "Delete buffer" })

-- Tab management
map("n", "<leader>tn", ":tabnew<CR>", { desc = "New tab" })
map("n", "<leader>tc", ":tabclose<CR>", { desc = "Close tab" })

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

-- Spell checking
map("n", "<leader>ss", ":setlocal spell!<CR>", { desc = "Toggle spell check" })

