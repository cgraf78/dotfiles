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

-- Continuously save session state so other nvim instances can load it.
-- Debounced to avoid hammering disk on rapid buffer changes (e.g. :argdo).
local save_timer = vim.uv.new_timer()
local function save_session_debounced()
  if not require("persistence").active() then
    return
  end
  save_timer:stop()
  save_timer:start(
    500,
    0,
    vim.schedule_wrap(function()
      require("persistence").save()
    end)
  )
end

vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete" }, {
  callback = save_session_debounced,
})

-- Auxiliary buffer types — IDE-style quit and session behavior.
--
-- Problem: nvim treats every window independently. :q from NvimTree or a
-- terminal just closes that window, requiring multiple :q to exit. And
-- session restore captures stale tool buffers that can't be meaningfully
-- restored (e.g. tool views with live data).
--
-- Solution: a single table (aux_buf_types) declares non-editor buffer types
-- and their policies. All behavior — :q exits nvim, auto-exit when no editor
-- windows remain, session save/restore, buffer cleanup — is derived from it.
--
-- Two kinds:
--   "panel"     — persistent sidebar/tool (NvimTree, terminal). Hidden from
--                 tabline, state saved/restored across sessions via sidecar.
--   "ephemeral" — transient tool view with live data (e.g. VCS log, blame).
--                 Visible in tabline while open, wiped on session save.
--
-- Both kinds: :q exits nvim, don't block auto-exit when last file closes.
-- Regular file buffers ("editor") are implicit — everything not listed here.
--
-- Minimal entry (ephemeral filetype — the common case):
--   { kind = "ephemeral", ft = "dap-repl" }
--   { kind = "ephemeral", ft = { "fugitive", "git" } }
--
-- Full entry (panel with custom behavior):
--   name:      sidecar file suffix (defaults to first ft or "unnamed")
--   kind:      "panel" or "ephemeral"
--   ft:        filetype pattern(s) — string or list. Auto-generates is_buf
--              and autocmd if not provided explicitly.
--   is_buf:    (override) predicate — does this buffer belong to this type?
--   close:     (panels) close the window before session save
--   open:      (panels) reopen on session restore
--   cleanup:   (optional) pre-delete cleanup (e.g. kill terminal jobs)
--   autocmd:   (override) { event, opts? } — when to set up buffer behaviors
--   on_create: (optional) additional buffer setup when the autocmd fires
--
-- To add a new auxiliary buffer type:
--   - Base types: add to aux_buf_types below.
--   - Plugin/overlay types: call require("config.autocmds").add({ ... })
--     from the plugin's config function.

local aux_buf_types = {}

local function setup_quit_abbrevs()
  vim.cmd("cnoreabbrev <buffer> q Qa")
  vim.cmd("cnoreabbrev <buffer> q! Qa!")
  vim.cmd("cnoreabbrev <buffer> wq Qa")
  vim.cmd("cnoreabbrev <buffer> wq! Qa!")
end

local function register_aux_type(entry)
  entry.name = entry.name
    or (type(entry.ft) == "string" and entry.ft or entry.ft and entry.ft[1] or "unnamed")

  if not entry.is_buf and entry.ft then
    local fts = type(entry.ft) == "string" and { entry.ft } or entry.ft
    local ft_set = {}
    for _, f in ipairs(fts) do
      ft_set[f] = true
    end
    entry.is_buf = function(buf)
      return ft_set[vim.bo[buf].filetype] or false
    end
  end

  if not entry.autocmd and entry.ft then
    entry.autocmd = {
      event = "FileType",
      opts = { pattern = type(entry.ft) == "string" and entry.ft or entry.ft },
    }
  end

  table.insert(aux_buf_types, entry)

  -- Late registration: if session already restored and this panel has a
  -- sidecar, restore it now. Handles plugins that register via add()
  -- after PersistenceLoadPost has already fired.
  if entry.kind == "panel" and entry.open then
    pcall(function()
      local path = sidecar_path(entry.name)
      if vim.fn.filereadable(path) == 1 then
        vim.schedule(function()
          entry.open()
        end)
      end
    end)
  end

  local ac = entry.autocmd
  vim.api.nvim_create_autocmd(
    ac.event,
    vim.tbl_extend("force", ac.opts or {}, {
      callback = function(args)
        if entry.kind == "panel" then
          vim.bo[args.buf].buflisted = false
        end
        if entry.on_create then
          entry.on_create(args.buf)
        end
        setup_quit_abbrevs()
      end,
    })
  )
end

-- Base types: always available.
register_aux_type({
  name = "nvimtree",
  kind = "panel",
  ft = "NvimTree",
  close = function()
    vim.cmd("silent! NvimTreeClose")
  end,
  open = function()
    vim.cmd("NvimTreeOpen")
  end,
})

register_aux_type({
  name = "terminal",
  kind = "panel",
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
})

local function is_auxiliary_buf(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  for _, entry in ipairs(aux_buf_types) do
    if entry.is_buf(buf) then
      return entry
    end
  end
  return false
end

local function aux_is_open(entry)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if entry.is_buf(vim.api.nvim_win_get_buf(win)) then
      return true
    end
  end
  return false
end

local function sidecar_path(name)
  return require("persistence").current() .. "." .. name
end

-- Guard: Qa calls save_aux_state() before deleting buffers, then :qa
-- triggers PersistenceSavePre which calls it again. Without this flag,
-- the second call sees panels already closed and deletes their sidecars.
local aux_state_saved = false

local function save_aux_state()
  if aux_state_saved then
    return
  end
  aux_state_saved = true
  for _, entry in ipairs(aux_buf_types) do
    if entry.kind == "panel" then
      local path = sidecar_path(entry.name)
      if aux_is_open(entry) then
        pcall(entry.close)
        vim.fn.writefile({}, path)
      else
        vim.fn.delete(path)
      end
    elseif entry.kind == "ephemeral" then
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) and entry.is_buf(buf) then
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
      end
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
      for _, entry in ipairs(aux_buf_types) do
        if entry.kind == "panel" and vim.fn.filereadable(sidecar_path(entry.name)) == 1 then
          pcall(entry.open)
        end
      end
      -- Focus an editor window so the cursor isn't left on a sidebar.
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_is_valid(buf) and not is_auxiliary_buf(buf) then
          vim.api.nvim_set_current_win(win)
          vim.cmd("stopinsert")
          break
        end
      end
    end)
  end,
})

-- :q from auxiliary buffers → :Qa (exit nvim).
-- Uses cnoreabbrev because nvim user commands must be uppercase and
-- QuitPre can't reliably delete buffers mid-quit.
-- Autocmds are registered per-entry inside register_aux_type() above.

vim.api.nvim_create_user_command("Qa", function(cmd)
  save_aux_state()

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local entry = is_auxiliary_buf(buf)
    if entry then
      if entry.cleanup then
        entry.cleanup(buf)
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

-- Auto-exit when no editor windows remain (only auxiliary panels visible).
-- Set vim.g.aux_exit_suppressed = true to temporarily prevent this during
-- programmatic window manipulation (e.g. moving a buffer between tabs).
vim.api.nvim_create_autocmd("WinClosed", {
  callback = function()
    vim.schedule(function()
      if vim.g.aux_exit_suppressed then
        return
      end
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_is_valid(buf) and not is_auxiliary_buf(buf) then
          return
        end
      end
      vim.cmd("Qa")
    end)
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

return {
  add = register_aux_type,
}
