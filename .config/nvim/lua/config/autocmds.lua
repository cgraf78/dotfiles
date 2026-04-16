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

-- Python: match VS Code's 4-space indentation.
vim.api.nvim_create_autocmd("FileType", {
  pattern = "python",
  callback = function()
    vim.opt_local.tabstop = 4
    vim.opt_local.shiftwidth = 4
    vim.opt_local.expandtab = true
  end,
})

-- Auto-restore session when opening nvim with no file arguments.
vim.api.nvim_create_autocmd("VimEnter", {
  nested = true,
  callback = function()
    if vim.fn.argc() == 0 and not vim.g.started_with_stdin then
      require("persistence").load()
    end
  end,
})

-- Detect stdin so auto-restore doesn't clobber piped input.
vim.api.nvim_create_autocmd("StdinReadPre", {
  callback = function() vim.g.started_with_stdin = true end,
})

-- Remember nvim-tree state across sessions. NvimTree buffers don't restore
-- cleanly from session files, so close the window before save but record
-- whether it was open via a sidecar file next to the session. On restore,
-- reopen if the sidecar exists.
vim.api.nvim_create_autocmd("User", {
  pattern = "PersistenceSavePre",
  callback = function()
    -- Clear arglist so stray files don't reappear on session restore.
    -- mksession always writes $argadd regardless of sessionoptions.
    vim.cmd("%argdelete")

    local sidecar = require("persistence").current() .. ".nvimtree"
    local was_open = false
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "NvimTree" then
        was_open = true
        vim.cmd("silent! NvimTreeClose")
        break
      end
    end
    if was_open then
      vim.fn.writefile({}, sidecar)
    else
      vim.fn.delete(sidecar)
    end
  end,
})
vim.api.nvim_create_autocmd("User", {
  pattern = "PersistenceLoadPost",
  callback = function()
    local sidecar = require("persistence").current() .. ".nvimtree"
    if vim.fn.filereadable(sidecar) == 1 then
      vim.schedule(function()
        vim.cmd("NvimTreeOpen")
      end)
    end
  end,
})

-- Make terminal buffers feel "live" when focused, like an IDE terminal.
vim.api.nvim_create_autocmd("BufEnter", {
  callback = function(args)
    if vim.bo[args.buf].buftype == "terminal" then
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(args.buf) and vim.api.nvim_get_current_buf() == args.buf then
          vim.cmd("startinsert")
        end
      end)
    end
  end,
})
