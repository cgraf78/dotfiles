-- ==========================================================================
--  Neovim config — migrated from amix/vimrc
--  Keeps: leader=comma, kj escape, 2-space tabs, key mappings you use
--  Drops: Windows/GUI compat, CoffeeScript/Mako/Twig, unused plugins
-- ==========================================================================

-- Leader key (must be set before plugins)
vim.g.mapleader = " "

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
local colorscheme = vim.env.NVIM_COLORSCHEME or vim.g.dot_colorscheme or "gruvbox"

local function lualine_theme(name)
  local supported = {
    gruvbox = true,
    tokyonight = true,
  }
  if supported[name] then
    return name
  end
  return "auto"
end

-- ── Options ──────────────────────────────────────────────────────────────

vim.opt.history = 500
vim.opt.autoread = true
vim.opt.mouse = "a"
vim.opt.clipboard = "unnamedplus"    -- system clipboard
vim.opt.termguicolors = true         -- 24-bit color
vim.opt.signcolumn = "yes"           -- always show sign column (no jitter)

-- UI
vim.opt.number = true                -- line numbers (amix didn't have this)
vim.opt.relativenumber = true        -- relative numbers for easy j/k jumps
vim.opt.scrolloff = 7                -- 7 lines visible above/below cursor
vim.opt.sidescrolloff = 8
vim.opt.wildmenu = true
vim.opt.wildignore = { "*.o", "*~", "*.pyc", "*/.git/*", "*/.hg/*", "*/.DS_Store" }
vim.opt.cmdheight = 1
vim.opt.hidden = true                -- allow hidden buffers
vim.opt.showmatch = true             -- highlight matching brackets
vim.opt.laststatus = 3               -- global statusline (neovim feature)
vim.opt.cursorline = true            -- highlight current line

-- Search
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = true
vim.opt.incsearch = true

-- Tabs & indentation (your override: 2 spaces)
vim.opt.expandtab = true
vim.opt.smarttab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.smartindent = true
vim.opt.wrap = true
vim.opt.linebreak = true             -- wrap at word boundaries

-- No backup/swap (source-controlled code)
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.swapfile = false

-- Persistent undo
vim.opt.undofile = true

-- Performance
vim.opt.updatetime = 250

-- Backspace behavior
vim.opt.backspace = { "eol", "start", "indent" }

-- Split behavior
vim.opt.splitbelow = true
vim.opt.splitright = true

-- ── Keymaps ──────────────────────────────────────────────────────────────

local map = vim.keymap.set

-- Escape from insert mode
map("i", "kj", "<Esc>")

-- Fast save
map("n", "<leader>w", ":w!<CR>")

-- Remap 0 to first non-blank character
map("n", "0", "^")

-- Clear search highlight
map("n", "<leader><CR>", ":noh<CR>", { silent = true })

-- Move between vim splits AND tmux panes (vim-tmux-navigator handles this)
-- Keymaps are set by the plugin below, no manual mapping needed

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

-- Return to last edit position when opening files
vim.api.nvim_create_autocmd("BufReadPost", {
  callback = function()
    local mark = vim.api.nvim_buf_get_mark(0, '"')
    local lines = vim.api.nvim_buf_line_count(0)
    if mark[1] > 1 and mark[1] <= lines then
      vim.api.nvim_win_set_cursor(0, mark)
    end
  end,
})

-- Auto-strip trailing whitespace on save for common filetypes
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = { "*.py", "*.js", "*.ts", "*.lua", "*.sh", "*.cpp", "*.h", "*.c" },
  callback = function()
    local pos = vim.api.nvim_win_get_cursor(0)
    vim.cmd([[%s/\s\+$//e]])
    vim.api.nvim_win_set_cursor(0, pos)
  end,
})

-- YAML: always 2-space indent
vim.api.nvim_create_autocmd("FileType", {
  pattern = "yaml",
  callback = function()
    vim.opt_local.tabstop = 2
    vim.opt_local.shiftwidth = 2
    vim.opt_local.expandtab = true
  end,
})

-- ── Plugins (lazy.nvim) ──────────────────────────────────────────────────

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({

  -- ── Colorscheme ──
  {
    "ellisonleao/gruvbox.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("gruvbox").setup({ contrast = "hard" })
      if colorscheme == "gruvbox" then
        vim.cmd("colorscheme gruvbox")
      end
    end,
  },
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("tokyonight").setup({
        style = "storm",
        styles = {
          comments = { italic = true },
          keywords = { italic = true },
          sidebars = "dark",
          floats = "dark",
        },
      })
      if colorscheme == "tokyonight" then
        vim.cmd("colorscheme tokyonight-storm")
      end
    end,
  },
  {
    "oxfist/night-owl.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      if colorscheme == "night-owl" then
        vim.cmd("colorscheme night-owl")
      end
    end,
  },
  {
    "rebelot/kanagawa.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("kanagawa").setup({
        theme = "wave",
        background = {
          dark = "wave",
          light = "lotus",
        },
      })
      if colorscheme == "kanagawa" then
        vim.cmd("colorscheme kanagawa-wave")
      end
    end,
  },
  {
    "nyoom-engineering/oxocarbon.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      if colorscheme == "oxocarbon" then
        vim.cmd("colorscheme oxocarbon")
      end
    end,
  },
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    config = function()
      require("catppuccin").setup({
        flavour = "mocha",
        integrations = {
          gitsigns = true,
          treesitter = true,
        },
      })
      if colorscheme == "catppuccin" then
        vim.cmd("colorscheme catppuccin")
      end
    end,
  },

  -- ── Statusline (replaces lightline) ──
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("lualine").setup({
        options = { theme = lualine_theme(colorscheme) },
        sections = {
          lualine_c = { { "filename", path = 1 } },  -- show relative path
        },
      })
    end,
  },

  -- ── Fuzzy finder (replaces CtrlP, MRU, BufExplorer, Ack) ──
  -- NOTE: find_files and live_grep search from CWD, not repo root.
  -- In fbsource, cd to your project dir first (e.g. arvr/libraries/proton).
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<C-f>", "<cmd>Telescope find_files<cr>", desc = "Find files" },
      { "<leader>f", "<cmd>Telescope oldfiles<cr>", desc = "Recent files" },
      { "<leader>b", "<cmd>Telescope buffers<cr>", desc = "Buffers" },
      { "<leader>g", "<cmd>Telescope live_grep<cr>", desc = "Live grep" },
      { "<leader>j", "<cmd>Telescope find_files<cr>", desc = "Find files" },
      { "<leader>/", "<cmd>Telescope current_buffer_fuzzy_find<cr>", desc = "Search in buffer" },
    },
    config = function()
      require("telescope").setup({
        defaults = {
          file_ignore_patterns = { "node_modules", "%.git/", "%.hg/", "%.o$", "%.pyc$" },
          -- Don't search from repo root — search from CWD (safe for fbsource)
          cwd = vim.fn.getcwd(),
        },
      })
    end,
  },

  -- ── File explorer (replaces NERDTree) ──
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    keys = {
      { "<leader>nn", "<cmd>NvimTreeToggle<cr>", desc = "Toggle file tree" },
      { "<leader>nf", "<cmd>NvimTreeFindFile<cr>", desc = "Find file in tree" },
    },
    config = function()
      require("nvim-tree").setup({
        view = { side = "right", width = 35 },
        filters = { dotfiles = false },
      })
    end,
  },

  -- ── Syntax highlighting (replaces regex-based) ──
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    event = "BufReadPost",
    config = function()
      vim.treesitter.language.add("c")
      vim.treesitter.language.add("cpp")
      vim.treesitter.language.add("python")
      vim.treesitter.language.add("lua")
      vim.treesitter.language.add("bash")
      vim.treesitter.language.add("json")
      vim.treesitter.language.add("yaml")
      vim.treesitter.language.add("javascript")
      vim.treesitter.language.add("typescript")
      vim.treesitter.language.add("markdown")
      vim.treesitter.language.add("rust")
      vim.treesitter.language.add("toml")
      vim.treesitter.language.add("cmake")
      vim.treesitter.language.add("make")
    end,
  },

  -- ── Git signs in gutter (replaces gitgutter, enabled by default) ──
  {
    "lewis6991/gitsigns.nvim",
    event = "BufReadPost",
    config = function()
      require("gitsigns").setup()
    end,
  },

  -- ── Autocompletion ──
  {
    "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",     -- LSP completions (functions, types, etc.)
      "hrsh7th/cmp-buffer",       -- words from current buffer
      "hrsh7th/cmp-path",         -- filesystem paths
      "L3MON4D3/LuaSnip",        -- snippet engine (required by nvim-cmp)
      "saadparwaiz1/cmp_luasnip", -- snippet completions
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")

      cmp.setup({
        snippet = {
          expand = function(args) luasnip.lsp_expand(args.body) end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-Space>"] = cmp.mapping.complete(),          -- trigger completion
          ["<CR>"] = cmp.mapping.confirm({ select = true }), -- accept selected
          ["<Tab>"] = cmp.mapping(function(fallback)        -- Tab to cycle
            if cmp.visible() then cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then luasnip.expand_or_jump()
            else fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then luasnip.jump(-1)
            else fallback()
            end
          end, { "i", "s" }),
          ["<C-e>"] = cmp.mapping.abort(),                 -- dismiss
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },   -- LSP suggestions first
          { name = "luasnip" },
        }, {
          { name = "buffer" },     -- fallback: words from buffer
          { name = "path" },       -- fallback: file paths
        }),
      })
    end,
  },

  -- ── LSP configs (provides server configs for vim.lsp.config) ──
  { "neovim/nvim-lspconfig", lazy = true },

  -- ── tmux integration ──
  {
    "christoomey/vim-tmux-navigator",  -- Ctrl+h/j/k/l moves between vim AND tmux panes
    lazy = false,
  },

  -- ── Editing helpers ──
  { "tpope/vim-surround" },           -- same plugin you had, works in nvim
  {
    "numToStr/Comment.nvim",           -- replaces vim-commentary
    event = "BufReadPost",
    config = function() require("Comment").setup() end,
  },
  {
    "windwp/nvim-autopairs",           -- replaces auto-pairs
    event = "InsertEnter",
    config = function() require("nvim-autopairs").setup() end,
  },

  -- ── which-key: shows available keybindings as you type ──
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    config = function()
      require("which-key").setup({
        delay = 500,
      })
    end,
  },

  -- ── Large file handling (disables slow features on big files) ──
  {
    "LunarVim/bigfile.nvim",
    event = "BufReadPre",
    config = function()
      require("bigfile").setup({ filesize = 2 })  -- 2 MB threshold
    end,
  },

}, {
  -- lazy.nvim options
  install = { colorscheme = { "gruvbox", "tokyonight", "night-owl", "kanagawa", "oxocarbon", "catppuccin" } },
  checker = { enabled = false },   -- don't auto-check for plugin updates
})

-- ── LSP (native vim.lsp.config, Neovim 0.11+) ─────────────────────────

-- Keymaps: only active when an LSP server is attached
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local opts = { buffer = ev.buf }
    map("n", "gd", vim.lsp.buf.definition, opts)           -- go to definition
    map("n", "gr", vim.lsp.buf.references, opts)           -- find references
    map("n", "K", vim.lsp.buf.hover, opts)                 -- hover docs
    map("n", "<leader>rn", vim.lsp.buf.rename, opts)       -- rename symbol
    map("n", "<leader>ca", vim.lsp.buf.code_action, opts)  -- code actions
    map("n", "[d", vim.diagnostic.goto_prev, opts)         -- prev diagnostic
    map("n", "]d", vim.diagnostic.goto_next, opts)         -- next diagnostic
  end,
})

-- nvim-cmp completion capabilities for LSP
local cmp_ok, cmp_lsp = pcall(require, "cmp_nvim_lsp")
local capabilities = cmp_ok and cmp_lsp.default_capabilities() or nil

-- C/C++ (install: sudo dnf install clang-tools-extra)
vim.lsp.config("clangd", { capabilities = capabilities })

-- Python (install: pip install pyright)
vim.lsp.config("pyright", { capabilities = capabilities })

-- Lua (for editing nvim config)
vim.lsp.config("lua_ls", {
  capabilities = capabilities,
  settings = {
    Lua = {
      runtime = { version = "LuaJIT" },
      workspace = { library = vim.api.nvim_get_runtime_file("", true) },
    },
  },
})

-- Bash (install: npm install -g bash-language-server)
vim.lsp.config("bashls", { capabilities = capabilities })

-- Enable all configured servers
vim.lsp.enable({ "clangd", "pyright", "lua_ls", "bashls" })
