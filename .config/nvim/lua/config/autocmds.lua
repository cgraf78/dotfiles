-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua

-- Diagnostic display: virtual text only for errors, rounded float borders,
-- source labels. Overrides LazyVim defaults for a quieter editor.
vim.diagnostic.config({
  severity_sort = true,
  float = {
    border = "rounded",
    source = true,
    header = "",
    prefix = "",
  },
  virtual_text = {
    prefix = "●",
    spacing = 2,
    severity = { min = vim.diagnostic.severity.ERROR },
  },
  signs = true,
  underline = true,
  update_in_insert = false,
})

vim.api.nvim_create_autocmd("StdinReadPre", {
  callback = function()
    vim.g.started_with_stdin = true
  end,
})

-- Save session continuously so crash recovery doesn't lose state.
local save_timer = vim.uv.new_timer()
vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete" }, {
  callback = function()
    local ok, persistence = pcall(require, "persistence")
    if not ok or type(persistence.active) ~= "function" or not persistence.active() then
      return
    end
    save_timer:stop()
    save_timer:start(
      500,
      0,
      vim.schedule_wrap(function()
        persistence.save()
      end)
    )
  end,
})

-- Cursor-hold auto-float: show diagnostics under the cursor when idle.
vim.api.nvim_create_autocmd("CursorHold", {
  callback = function()
    local bt = vim.bo.buftype
    if bt == "prompt" or bt == "terminal" or bt == "nofile" then
      return
    end
    vim.diagnostic.open_float(nil, { focus = false, scope = "cursor" })
  end,
})
