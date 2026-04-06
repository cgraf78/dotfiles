local theme = require("config.theme")

return {
  {
    "ellisonleao/gruvbox.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("gruvbox").setup({ contrast = "hard" })
      if theme.colorscheme == "gruvbox" then
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
      if theme.colorscheme == "tokyonight" then
        vim.cmd("colorscheme tokyonight-storm")
      end
    end,
  },
  {
    "oxfist/night-owl.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      if theme.colorscheme == "night-owl" then
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
      if theme.colorscheme == "kanagawa" then
        vim.cmd("colorscheme kanagawa-wave")
      end
    end,
  },
  {
    "nyoom-engineering/oxocarbon.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      if theme.colorscheme == "oxocarbon" then
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
      if theme.colorscheme == "catppuccin" then
        vim.cmd("colorscheme catppuccin")
      end
    end,
  },
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("lualine").setup({
        options = { theme = theme.lualine_theme() },
        sections = {
          lualine_c = { { "filename", path = 1 } },
        },
      })
    end,
  },
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
          cwd = vim.fn.getcwd(),
        },
      })
    end,
  },
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
  {
    "lewis6991/gitsigns.nvim",
    event = "BufReadPost",
    config = function()
      require("gitsigns").setup()
    end,
  },
  {
    "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "L3MON4D3/LuaSnip",
      "saadparwaiz1/cmp_luasnip",
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")

      cmp.setup({
        snippet = {
          expand = function(args) luasnip.lsp_expand(args.body) end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<CR>"] = cmp.mapping.confirm({ select = true }),
          ["<Tab>"] = cmp.mapping(function(fallback)
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
          ["<C-e>"] = cmp.mapping.abort(),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
        }, {
          { name = "buffer" },
          { name = "path" },
        }),
      })
    end,
  },
  { "neovim/nvim-lspconfig", lazy = true },
  {
    "christoomey/vim-tmux-navigator",
    lazy = false,
  },
  { "tpope/vim-surround" },
  {
    "numToStr/Comment.nvim",
    event = "BufReadPost",
    config = function() require("Comment").setup() end,
  },
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = function() require("nvim-autopairs").setup() end,
  },
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    config = function()
      require("which-key").setup({
        delay = 500,
      })
    end,
  },
  {
    "LunarVim/bigfile.nvim",
    event = "BufReadPre",
    config = function()
      require("bigfile").setup({ filesize = 2 })
    end,
  },
}
