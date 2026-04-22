local theme = require("config.theme")

return {
  {
    "ellisonleao/gruvbox.nvim",
    lazy = theme.colorscheme ~= "gruvbox",
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
    lazy = theme.colorscheme ~= "tokyonight",
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
    lazy = theme.colorscheme ~= "night-owl",
    priority = 1000,
    config = function()
      if theme.colorscheme == "night-owl" then
        vim.cmd("colorscheme night-owl")
        theme.apply_overrides()
      end
    end,
  },
  {
    "rebelot/kanagawa.nvim",
    lazy = theme.colorscheme ~= "kanagawa",
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
    lazy = theme.colorscheme ~= "oxocarbon",
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
    lazy = theme.colorscheme ~= "catppuccin",
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
      local buffers = require("config.buffers")

      require("bufferline").setup({
        options = {
          mode = "buffers",
          diagnostics = "nvim_lsp",
          always_show_bufferline = true,
          close_command = buffers.delete,
          right_mouse_command = buffers.delete,
          middle_mouse_command = buffers.delete,
          show_buffer_close_icons = true,
          show_close_icon = false,
          separator_style = "slant",
        },
      })
    end,
  },
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = "markdown",
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
    config = function()
      -- Night-owl-friendly heading backgrounds (blues/teals).
      -- Only applied when night-owl is active; other themes use defaults.
      if theme.colorscheme == "night-owl" then
        vim.api.nvim_set_hl(0, "RenderMarkdownH1Bg", { bg = "#1d3b53" })
        vim.api.nvim_set_hl(0, "RenderMarkdownH2Bg", { bg = "#112630" })
        vim.api.nvim_set_hl(0, "RenderMarkdownH3Bg", { bg = "#0e293f" })
        vim.api.nvim_set_hl(0, "RenderMarkdownH4Bg", { bg = "#0b253a" })
        vim.api.nvim_set_hl(0, "RenderMarkdownH5Bg", { bg = "#092135" })
        vim.api.nvim_set_hl(0, "RenderMarkdownH6Bg", { bg = "#071d30" })
      end
      require("render-markdown").setup({})
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
}
