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
    "*.py",
    "*.js",
    "*.ts",
    "*.tsx",
    "*.lua",
    "*.sh",
    "*.c",
    "*.cpp",
    "*.h",
    "*.hpp",
    "*.rs",
    "*.toml",
    "*.json",
    "*.yaml",
    "*.yml",
    "*.md",
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
  callback = function()
    vim.g.started_with_stdin = true
  end,
})

-- Persist auxiliary buffer state across sessions. These buffers don't restore
-- from session files, so we record which were open via sidecar files next to
-- the session and reopen them on restore.
--
-- Each entry in aux_panel_types:
--   name:      sidecar file suffix for session persistence
--   is_buf:    predicate — does this buffer belong to this panel?
--   close:     close the panel window before session save
--   open:      reopen the panel on session restore
--   cleanup:   (optional) pre-delete cleanup (e.g. kill terminal jobs)
--   autocmd:   { event, opts? } — when to set up :q abbreviations
--   on_create: (optional) buffer setup when the autocmd fires
--
-- is_open() is derived from is_buf() — no need to define it per panel.
--
-- To add a new auxiliary panel type, add one entry here. Everything else
-- (session save/restore, :q behavior, buffer deletion) flows from it.
local aux_panel_types = {
  {
    name = "nvimtree",
    is_buf = function(buf)
      return vim.bo[buf].filetype == "NvimTree"
    end,
    close = function()
      vim.cmd("silent! NvimTreeClose")
    end,
    open = function()
      vim.cmd("NvimTreeOpen")
    end,
    autocmd = { event = "FileType", opts = { pattern = "NvimTree" } },
  },
  {
    name = "terminal",
    is_buf = function(buf)
      return vim.bo[buf].buftype == "terminal"
    end,
    close = function() end,
    open = function()
      require("config.terminal").open_bottom()
    end,
    cleanup = function(buf)
      local job = vim.b[buf].terminal_job_id
      if job then
        pcall(vim.fn.jobstop, job)
        pcall(vim.fn.jobwait, { job }, 100)
      end
    end,
    autocmd = { event = "TermOpen" },
    on_create = function(buf)
      vim.bo[buf].buflisted = false
    end,
  },
}

local function panel_is_open(panel)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if panel.is_buf(vim.api.nvim_win_get_buf(win)) then
      return true
    end
  end
  return false
end

local function sidecar_path(name)
  return require("persistence").current() .. "." .. name
end

local aux_state_saved = false

local function save_aux_state()
  if aux_state_saved then
    return
  end
  aux_state_saved = true
  for _, panel in ipairs(aux_panel_types) do
    local path = sidecar_path(panel.name)
    if panel_is_open(panel) then
      panel.close()
      vim.fn.writefile({}, path)
    else
      vim.fn.delete(path)
    end
  end
end

vim.api.nvim_create_autocmd("User", {
  pattern = "PersistenceSavePre",
  callback = function()
    vim.cmd("%argdelete")
    save_aux_state()
  end,
})

vim.api.nvim_create_autocmd("User", {
  pattern = "PersistenceLoadPost",
  callback = function()
    vim.schedule(function()
      for _, panel in ipairs(aux_panel_types) do
        if vim.fn.filereadable(sidecar_path(panel.name)) == 1 then
          panel.open()
        end
      end
    end)
  end,
})

-- IDE-style :q — exit nvim from any auxiliary buffer (terminal, NvimTree).
--
-- Without this, :q from a terminal or tree sidebar just closes that window,
-- requiring a second :q to actually exit. This makes :q behave like closing
-- the IDE window: quit everything, but warn about unsaved file changes.
--
-- Mechanism: buffer-local cnoreabbrev expands :q to :Qa in auxiliary buffers.
-- We can't use lowercase user commands (nvim requires uppercase) or QuitPre
-- (can't reliably delete buffers mid-quit), so the abbreviation trick is the
-- only approach that works.

local function setup_quit_abbrevs()
  vim.cmd("cnoreabbrev <buffer> q Qa")
  vim.cmd("cnoreabbrev <buffer> q! Qa!")
  vim.cmd("cnoreabbrev <buffer> wq Qa")
  vim.cmd("cnoreabbrev <buffer> wq! Qa!")
end

for _, panel in ipairs(aux_panel_types) do
  local ac = panel.autocmd
  vim.api.nvim_create_autocmd(
    ac.event,
    vim.tbl_extend("force", ac.opts or {}, {
      callback = function(args)
        if panel.on_create then
          panel.on_create(args.buf)
        end
        setup_quit_abbrevs()
      end,
    })
  )
end

local function is_auxiliary_buf(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  for _, panel in ipairs(aux_panel_types) do
    if panel.is_buf(buf) then
      return panel
    end
  end
  return false
end

vim.api.nvim_create_user_command("Qa", function(cmd)
  save_aux_state()

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local panel = is_auxiliary_buf(buf)
    if panel then
      if panel.cleanup then
        panel.cleanup(buf)
      end
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
  -- :qa warns about unsaved file buffers (E37); :qa! discards them.
  local ok, err = pcall(vim.cmd, cmd.bang and "qa!" or "qa")
  if not ok then
    vim.notify(err:gsub("^.*:E", "E"), vim.log.levels.ERROR)
  end
end, { bang = true })

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
