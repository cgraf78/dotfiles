-- Leader key (must be set before plugins)
vim.g.mapleader = " "

-- ── Options ──────────────────────────────────────────────────────────────

vim.opt.history = 500
vim.opt.autoread = true
vim.opt.mouse = "a"
vim.opt.clipboard = "unnamedplus"
vim.opt.termguicolors = true
vim.opt.signcolumn = "yes"

-- UI
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.scrolloff = 7
vim.opt.sidescrolloff = 8
vim.opt.wildmenu = true
vim.opt.wildignore = { "*.o", "*~", "*.pyc", "*/.git/*", "*/.hg/*", "*/.DS_Store" }
vim.opt.cmdheight = 1
vim.opt.hidden = true
vim.opt.showmatch = true
vim.opt.laststatus = 3
vim.opt.cursorline = true

-- Search
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = true
vim.opt.incsearch = true

-- Tabs & indentation
vim.opt.expandtab = true
vim.opt.smarttab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.smartindent = true
vim.opt.wrap = true
vim.opt.linebreak = true

-- No backup/swap
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.swapfile = false

-- Persistent undo
vim.opt.undofile = true

-- Performance
vim.opt.timeoutlen = 300
vim.opt.updatetime = 250

-- Backspace behavior
vim.opt.backspace = { "eol", "start", "indent" }

-- Split behavior
vim.opt.splitbelow = true
vim.opt.splitright = true

-- Session: save only layout and current files, not stray buffers or arglists
vim.opt.sessionoptions = { "curdir", "folds", "tabpages", "winsize", "winpos" }
