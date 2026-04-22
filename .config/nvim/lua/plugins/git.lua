return {
  {
    "tpope/vim-fugitive",
    cmd = { "Git", "Gdiffsplit", "Gvdiffsplit" },
    keys = {
      { "<leader>gs", "<cmd>Git<cr>", desc = "Git status" },
      { "<leader>gd", "<cmd>Gvdiffsplit<cr>", desc = "Git diff split" },
    },
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
          map(
            "n",
            "<leader>hp",
            gs.preview_hunk,
            vim.tbl_extend("force", opts, { desc = "Preview hunk" })
          )
          map(
            "n",
            "<leader>hr",
            gs.reset_hunk,
            vim.tbl_extend("force", opts, { desc = "Reset hunk" })
          )
          map(
            "n",
            "<leader>hs",
            gs.stage_hunk,
            vim.tbl_extend("force", opts, { desc = "Stage hunk" })
          )
          map("n", "<leader>hb", function()
            gs.blame_line({ full = true })
          end, vim.tbl_extend("force", opts, { desc = "Blame line" }))
          map(
            "n",
            "<leader>hB",
            gs.toggle_current_line_blame,
            vim.tbl_extend("force", opts, { desc = "Toggle inline blame" })
          )
        end,
      })
    end,
  },
}
