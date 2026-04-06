local map = vim.keymap.set

-- Escape from insert mode
map("i", "kj", "<Esc>")

-- Fast save
map("n", "<leader>w", ":w!<CR>")

-- Remap 0 to first non-blank character
map("n", "0", "^")

-- Clear search highlight
map("n", "<leader><CR>", ":noh<CR>", { silent = true })

-- Buffer navigation
map("n", "<leader>l", ":bnext<CR>")
map("n", "<leader>h", ":bprevious<CR>")
map("n", "<leader>bd", ":bdelete<CR>")

-- Tab management
map("n", "<leader>tn", ":tabnew<CR>")
map("n", "<leader>tc", ":tabclose<CR>")

-- Move lines with Alt+j/k
map("n", "<M-j>", ":m .+1<CR>==")
map("n", "<M-k>", ":m .-2<CR>==")
map("v", "<M-j>", ":m '>+1<CR>gv=gv")
map("v", "<M-k>", ":m '<-2<CR>gv=gv")

-- Visual mode: search for selection with * and #
map("v", "*", [[y/\V<C-R>=escape(@",'/\')<CR><CR>]])
map("v", "#", [[y?\V<C-R>=escape(@",'/\')<CR><CR>]])

-- Strip trailing whitespace
map("n", "<F5>", function()
  local pos = vim.api.nvim_win_get_cursor(0)
  vim.cmd([[%s/\s\+$//e]])
  vim.api.nvim_win_set_cursor(0, pos)
end, { desc = "Strip trailing whitespace" })

-- Spell checking
map("n", "<leader>ss", ":setlocal spell!<CR>")
