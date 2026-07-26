local M = {}

local function follow_item()
  require("nvim_workspace.navigation").goto_mouse()
end

local function open_lazygit()
  if not rawget(_G, "Snacks") then
    pcall(require, "snacks")
  end

  local opts = require("nvim_workspace.lazygit").opts()
  require("snacks.lazygit").open(opts)
end

function M.setup()
  -- Terminals default Ctrl-click to tag lookup, which bypasses LSP. Route it
  -- through nvim-workspace so local and remote sessions share the same
  -- definition/root policy.
  vim.keymap.set("n", "<C-LeftMouse>", follow_item, { desc = "Follow Item" })

  -- LazyVim also owns <leader>gg. The workspace plugin spec calls this setup
  -- after VeryLazy so this map keeps nvim-workspace's root and bare-repo
  -- policy while still overriding LazyVim's default lazygit binding.
  if vim.fn.executable("lazygit") == 1 then
    vim.keymap.set("n", "<leader>gg", open_lazygit, { desc = "Lazygit (Root Dir)" })
  end
end

return M
