-- Change default theme here:
local colorscheme = vim.env.NVIM_COLORSCHEME or "tokyonight"

return {
  { "LazyVim/LazyVim", opts = { colorscheme = colorscheme } },

  {
    "folke/tokyonight.nvim",
    opts = {
      style = "storm",
      styles = {
        comments = { italic = true },
        keywords = { italic = true },
        sidebars = "normal",
        floats = "dark",
      },
    },
  },

  {
    "ellisonleao/gruvbox.nvim",
    lazy = colorscheme ~= "gruvbox",
    priority = 1000,
    opts = { contrast = "hard" },
    config = function(_, opts)
      require("gruvbox").setup(opts)
      if colorscheme == "gruvbox" then
        vim.cmd("colorscheme gruvbox")
      end
    end,
  },

  {
    "oxfist/night-owl.nvim",
    lazy = colorscheme ~= "night-owl",
    priority = 1000,
    config = function()
      if colorscheme == "night-owl" then
        local dim = "#384050"
        local overrides = {
          CursorLine = { bg = "#0b2942" },
          SnacksIndent = { fg = dim },
          SnacksIndentScope = { fg = dim },
          Whitespace = { fg = dim },
        }
        local function apply()
          for group, hl in pairs(overrides) do
            vim.api.nvim_set_hl(0, group, hl)
          end
        end
        vim.cmd("colorscheme night-owl")
        apply()
        vim.api.nvim_create_autocmd("ColorScheme", {
          pattern = "night-owl",
          callback = apply,
        })
      end
    end,
  },

  {
    "rebelot/kanagawa.nvim",
    lazy = colorscheme ~= "kanagawa",
    priority = 1000,
    opts = {
      theme = "wave",
      background = { dark = "wave", light = "lotus" },
    },
    config = function(_, opts)
      require("kanagawa").setup(opts)
      if colorscheme == "kanagawa" then
        vim.cmd("colorscheme kanagawa-wave")
      end
    end,
  },

  {
    "nyoom-engineering/oxocarbon.nvim",
    lazy = colorscheme ~= "oxocarbon",
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
    lazy = colorscheme ~= "catppuccin",
    priority = 1000,
    opts = {
      flavour = "mocha",
      integrations = { gitsigns = true, treesitter = true },
    },
    config = function(_, opts)
      require("catppuccin").setup(opts)
      if colorscheme == "catppuccin" then
        vim.cmd("colorscheme catppuccin")
      end
    end,
  },
}
