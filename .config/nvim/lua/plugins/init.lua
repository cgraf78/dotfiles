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
    "akinsho/bufferline.nvim",
    version = "*",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("bufferline").setup({
        options = {
          mode = "buffers",
          diagnostics = "nvim_lsp",
          always_show_bufferline = true,
          show_buffer_close_icons = false,
          show_close_icon = false,
          separator_style = "slant",
        },
      })
    end,
  },
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    event = "BufReadPost",
    config = function()
      require("ibl").setup({
        indent = { char = "│" },
        scope = { enabled = true },
      })
    end,
  },
  {
    "folke/trouble.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    keys = {
      { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", desc = "Diagnostics" },
      { "<leader>xw", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "Buffer diagnostics" },
      { "<leader>xs", "<cmd>Trouble symbols toggle focus=false<cr>", desc = "Symbols" },
      { "<leader>xl", "<cmd>Trouble lsp toggle focus=false win.position=right<cr>", desc = "LSP definitions / refs" },
      { "<leader>xq", "<cmd>Trouble qflist toggle<cr>", desc = "Quickfix list" },
    },
    config = function()
      require("trouble").setup({})
    end,
  },
  {
    "stevearc/aerial.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    keys = {
      { "<leader>a", "<cmd>AerialToggle!<cr>", desc = "Symbols outline" },
    },
    config = function()
      require("aerial").setup({
        backends = { "lsp", "treesitter", "markdown", "asciidoc", "man" },
        layout = {
          default_direction = "right",
          min_width = 28,
        },
      })
    end,
  },
  {
    "folke/persistence.nvim",
    event = "BufReadPre",
    opts = {},
    keys = {
      { "<leader>qs", function() require("persistence").load() end, desc = "Restore session" },
      { "<leader>ql", function() require("persistence").load({ last = true }) end, desc = "Restore last session" },
      { "<leader>qd", function() require("persistence").stop() end, desc = "Stop saving session" },
    },
  },
  {
    "doctorfree/cheatsheet.nvim",
    dependencies = { "nvim-telescope/telescope.nvim", "nvim-lua/plenary.nvim" },
    cmd = "Cheatsheet",
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
      { "<leader>?", "<cmd>Telescope keymaps<cr>", desc = "Search keymaps" },
      { "<leader>sv", "<cmd>Cheatsheet<cr>", desc = "Vim cheatsheet" },
      { "<leader>sh", "<cmd>Telescope help_tags<cr>", desc = "Search help" },
      { "<leader>sc", "<cmd>Telescope commands<cr>", desc = "Search commands" },
    },
    config = function()
      local find_command = nil
      if vim.fn.executable("fd") == 1 then
        find_command = {
          "fd",
          "--type", "f",
          "--hidden",
          "--follow",
          "--exclude", ".git",
          "--exclude", "Library",
          "--exclude", "Applications",
          "--exclude", ".local/share/Steam",
        }
      end

      require("telescope").setup({
        defaults = {
          file_ignore_patterns = {
            "node_modules",
            "%.git/",
            "%.hg/",
            "%.o$",
            "%.pyc$",
            "^Library/",
            "^Applications/",
            "^%.local/share/Steam/",
          },
          cwd = vim.fn.getcwd(),
        },
        pickers = {
          find_files = {
            hidden = true,
            find_command = find_command,
          },
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
      require("gitsigns").setup({
        on_attach = function(bufnr)
          local gs = package.loaded.gitsigns
          local map = vim.keymap.set
          local opts = { buffer = bufnr }

          map("n", "]h", gs.next_hunk, vim.tbl_extend("force", opts, { desc = "Next hunk" }))
          map("n", "[h", gs.prev_hunk, vim.tbl_extend("force", opts, { desc = "Previous hunk" }))
          map("n", "<leader>hp", gs.preview_hunk, vim.tbl_extend("force", opts, { desc = "Preview hunk" }))
          map("n", "<leader>hr", gs.reset_hunk, vim.tbl_extend("force", opts, { desc = "Reset hunk" }))
          map("n", "<leader>hs", gs.stage_hunk, vim.tbl_extend("force", opts, { desc = "Stage hunk" }))
          map("n", "<leader>hb", function() gs.blame_line({ full = true }) end, vim.tbl_extend("force", opts, { desc = "Blame line" }))
          map("n", "<leader>hB", gs.toggle_current_line_blame, vim.tbl_extend("force", opts, { desc = "Toggle inline blame" }))
        end,
      })
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
  { "b0o/schemastore.nvim", lazy = true },
  {
    "williamboman/mason.nvim",
    build = ":MasonUpdate",
    config = function()
      require("mason").setup()
    end,
  },
  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = { "williamboman/mason.nvim", "neovim/nvim-lspconfig" },
    config = function()
      require("mason-lspconfig").setup({
        ensure_installed = {
          "bashls",
          "clangd",
          "jsonls",
          "lua_ls",
          "marksman",
          "pyright",
          "rust_analyzer",
          "ts_ls",
          "yamlls",
        },
        automatic_enable = false, -- lsp.lua handles vim.lsp.enable
      })
    end,
  },
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = { "williamboman/mason.nvim" },
    config = function()
      require("mason-tool-installer").setup({
        ensure_installed = {
          "eslint_d",
          "prettier",
          "ruff",
          "shfmt",
          "stylua",
          "taplo",
        },
      })
    end,
  },
  {
    "stevearc/conform.nvim",
    event = "BufWritePre",
    keys = {
      {
        "<leader>cf",
        function() require("conform").format({ async = true }) end,
        desc = "Format buffer",
      },
    },
    config = function()
      require("conform").setup({
        formatters_by_ft = {
          bash = { "shfmt" },
          c = { "clang-format" },
          cpp = { "clang-format" },
          css = { "prettier" },
          html = { "prettier" },
          javascript = { "prettier" },
          javascriptreact = { "prettier" },
          json = { "prettier" },
          lua = { "stylua" },
          markdown = { "prettier" },
          python = { "ruff_format" },
          rust = { "rustfmt" },
          sh = { "shfmt" },
          toml = { "taplo" },
          typescript = { "prettier" },
          typescriptreact = { "prettier" },
          yaml = { "prettier" },
        },
        format_on_save = function(bufnr)
          -- Skip if formatter not installed
          if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
            return
          end
          return { timeout_ms = 2000, lsp_format = "fallback" }
        end,
      })
    end,
  },
  {
    "mfussenegger/nvim-lint",
    event = { "BufReadPost", "BufWritePost", "InsertLeave" },
    config = function()
      local lint = require("lint")
      lint.linters_by_ft = {
        bash = { "shellcheck" },
        javascript = { "eslint_d" },
        javascriptreact = { "eslint_d" },
        python = { "ruff" },
        sh = { "shellcheck" },
        typescript = { "eslint_d" },
        typescriptreact = { "eslint_d" },
      }
      vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "InsertLeave" }, {
        callback = function()
          lint.try_lint()
        end,
      })
    end,
  },
  {
    "christoomey/vim-tmux-navigator",
    lazy = false,
  },
  { "tpope/vim-surround" },
  {
    "mbbill/undotree",
    keys = {
      { "<leader>u", "<cmd>UndotreeToggle<cr>", desc = "Toggle undo tree" },
    },
  },
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
      local wk = require("which-key")
      wk.setup({ delay = 500 })
      wk.add({
        { "<leader>b", group = "buffer" },
        { "<leader>c", group = "code" },
        { "<leader>h", group = "git hunk" },
        { "<leader>n", group = "file tree" },
        { "<leader>q", group = "session" },
        { "<leader>r", group = "rename" },
        { "<leader>s", group = "spell" },
        { "<leader>t", group = "toggle/tab" },
        { "<leader>x", group = "diagnostics" },
        { "g", group = "goto" },
        { "[", group = "previous" },
        { "]", group = "next" },
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
