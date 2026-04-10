return {
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
    dependencies = {
      "nvim-lua/plenary.nvim",
      {
        "nvim-telescope/telescope-fzf-native.nvim",
        build = "make",
        cond = function() return vim.fn.executable("make") == 1 end,
      },
    },
    keys = {
      { "<C-p>", "<cmd>Telescope find_files<cr>", desc = "Find files" },
      { "<C-f>", "<cmd>Telescope current_buffer_fuzzy_find<cr>", desc = "Search in buffer" },
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
      require("telescope").setup({
        defaults = {
          cwd = vim.fn.getcwd(),
          layout_strategy = "vertical",
          layout_config = {
            vertical = {
              mirror = true,
              preview_height = 0.45,
              prompt_position = "top",
            },
          },
          sorting_strategy = "ascending",
        },
        pickers = {
          find_files = {
            hidden = true,
            find_command = { "fd", "--type", "f", "--hidden" },
          },
        },
      })
      pcall(require("telescope").load_extension, "fzf")
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
        view = { side = "left", width = 35 },
        filters = { dotfiles = false },
        update_focused_file = {
          enable = true,
          update_root = false,
        },
      })
    end,
  },
  {
    "mbbill/undotree",
    keys = {
      { "<leader>u", "<cmd>UndotreeToggle<cr>", desc = "Toggle undo tree" },
    },
  },
  {
    "christoomey/vim-tmux-navigator",
    lazy = false,
  },
  {
    "LunarVim/bigfile.nvim",
    event = "BufReadPre",
    config = function()
      require("bigfile").setup({ filesize = 2 })
    end,
  },
}
