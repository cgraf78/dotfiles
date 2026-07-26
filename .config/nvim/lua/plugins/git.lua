return {
  {
    "lewis6991/gitsigns.nvim",
    opts = {
      current_line_blame = true,
      current_line_blame_opts = { delay = 300 },
    },
  },

  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose", "DiffviewRefresh" },
    keys = {
      { "<leader>dv", "<cmd>DiffviewOpen<cr>", desc = "Diff changes" },
      {
        "<leader>df",
        function()
          local file = vim.fn.expand("%")
          if file == "" then
            vim.cmd("DiffviewOpen")
          else
            vim.cmd("DiffviewOpen -- " .. vim.fn.fnameescape(file))
          end
        end,
        desc = "Diff current file",
      },
      { "<leader>dr", "<cmd>DiffviewRefresh<cr>", desc = "Refresh diff view" },
      { "<leader>dh", "<cmd>DiffviewFileHistory %<cr>", desc = "File history" },
      { "<leader>dc", "<cmd>DiffviewClose<cr>", desc = "Close diff view" },
    },
    opts = function()
      local actions = require("diffview.actions")
      local function cycle_layout_maps()
        return {
          { "n", "<C-x>", actions.cycle_layout, { desc = "Cycle diff layout" } },
          { "n", "<leader>dx", actions.cycle_layout, { desc = "Cycle diff layout" } },
        }
      end

      local function view_maps()
        local maps = cycle_layout_maps()
        -- Keep these view-local so the global Ctrl-Up/Down function-jump
        -- mappings still apply everywhere outside Diffview's diff buffers.
        vim.list_extend(maps, {
          { "n", "<C-Up>", "[c", { desc = "Previous diff hunk" } },
          { "n", "<C-Down>", "]c", { desc = "Next diff hunk" } },
        })
        return maps
      end

      return {
        view = {
          default = {
            -- Diffview names this layout "vertical", but it creates `:sp`
            -- windows: the old and new buffers are stacked top/bottom.
            layout = "diff2_vertical",
          },
        },
        keymaps = {
          view = view_maps(),
          file_panel = cycle_layout_maps(),
          file_history_panel = cycle_layout_maps(),
        },
      }
    end,
  },
}
