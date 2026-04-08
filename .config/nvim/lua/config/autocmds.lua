-- Return to last edit position when opening files
vim.api.nvim_create_autocmd("BufReadPost", {
  callback = function()
    local mark = vim.api.nvim_buf_get_mark(0, '"')
    local lines = vim.api.nvim_buf_line_count(0)
    if mark[1] > 1 and mark[1] <= lines then
      vim.api.nvim_win_set_cursor(0, mark)
    end
  end,
})

-- Auto-strip trailing whitespace on save for common filetypes
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = {
    "*.py", "*.js", "*.ts", "*.tsx", "*.lua", "*.sh",
    "*.c", "*.cpp", "*.h", "*.hpp",
    "*.rs", "*.toml", "*.json", "*.yaml", "*.yml", "*.md",
  },
  callback = function()
    local pos = vim.api.nvim_win_get_cursor(0)
    vim.cmd([[%s/\s\+$//e]])
    vim.api.nvim_win_set_cursor(0, pos)
  end,
})

-- YAML: always 2-space indent
vim.api.nvim_create_autocmd("FileType", {
  pattern = "yaml",
  callback = function()
    vim.opt_local.tabstop = 2
    vim.opt_local.shiftwidth = 2
    vim.opt_local.expandtab = true
  end,
})
