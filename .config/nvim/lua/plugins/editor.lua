return {
  {
    "folke/snacks.nvim",
    opts = {
      dashboard = { enabled = false },
      scroll = { enabled = false },
      animate = { enabled = false },
    },
  },

  {
    "folke/persistence.nvim",
    opts = {},
    init = function()
      vim.api.nvim_create_autocmd("VimEnter", {
        nested = true,
        callback = function()
          if
            vim.fn.argc() == 0
            and not vim.g.started_with_stdin
            and not vim.g.disable_session_restore
          then
            require("persistence").load()
            vim.schedule(function()
              for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                local name = vim.api.nvim_buf_get_name(buf)
                if name ~= "" and not vim.uv.fs_stat(name) then
                  vim.api.nvim_buf_delete(buf, { force = true })
                end
              end
              if vim.api.nvim_buf_get_name(0) ~= "" then
                vim.cmd("filetype detect")
                vim.cmd("edit")
              end
            end)
          end
        end,
      })
    end,
  },

  {
    "lewis6991/gitsigns.nvim",
    opts = {
      current_line_blame = true,
      current_line_blame_opts = { delay = 300 },
    },
  },

  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewFileHistory" },
    keys = {
      { "<leader>dv", "<cmd>DiffviewOpen<cr>", desc = "Diff view" },
      { "<leader>dh", "<cmd>DiffviewFileHistory %<cr>", desc = "File history" },
      { "<leader>dc", "<cmd>DiffviewClose<cr>", desc = "Close diff view" },
    },
    opts = {},
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
    "nvim-neo-tree/neo-tree.nvim",
    keys = {
      {
        "<leader>fe",
        function()
          require("neo-tree.command").execute({ toggle = true, reveal = true, dir = LazyVim.root() })
        end,
        desc = "Explorer NeoTree (Root Dir)",
      },
      {
        "<leader>fE",
        function()
          require("neo-tree.command").execute({
            action = "focus",
            reveal = true,
            dir = vim.env.HOME,
          })
        end,
        desc = "Explorer NeoTree (Home)",
      },
    },
    opts = function()
      local large = in_large_repo()
      return {
        enable_git_status = not large,
        filesystem = {
          use_libuv_file_watcher = not large,
          follow_current_file = { enabled = true },
          filtered_items = {
            hide_dotfiles = false,
            hide_gitignored = not large,
            hide_ignored = not large,
            ignore_files = not large and { ".neotreeignore", ".ignore" } or {},
          },
        },
      }
    end,
  },

  {
    "nvim-telescope/telescope.nvim",
    keys = {
      {
        "<C-p>",
        function()
          require("config.file-finder").find()
        end,
        desc = "Find files",
      },
      {
        "<leader><space>",
        function()
          require("config.file-finder").find()
        end,
        desc = "Find files",
      },
      {
        "<leader>ff",
        function()
          require("config.file-finder").find()
        end,
        desc = "Find files",
      },
      {
        "<leader>fF",
        function()
          require("config.file-finder").find()
        end,
        desc = "Find files",
      },
      {
        "<leader>fg",
        function()
          require("config.file-finder").find()
        end,
        desc = "Find files",
      },
      {
        "<C-f>",
        function()
          require("telescope.builtin").current_buffer_fuzzy_find({ initial_mode = "insert" })
        end,
        desc = "Search in buffer",
      },
      {
        "<C-S-f>",
        function()
          require("config.file-search").find()
        end,
        desc = "Search in files",
      },
      {
        "<C-S-p>",
        function()
          require("config.command-palette").open()
        end,
        desc = "Command palette",
      },
    },
  },
}
