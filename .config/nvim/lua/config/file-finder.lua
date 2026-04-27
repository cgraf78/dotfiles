-- Async file picker: shows recent files instantly, then progressively merges
-- live fd results as you type. Extensible via add_source() so overlay configs
-- can plug in additional search backends without touching this file.

local M = {}

M.sources = {}

--- Register a file-finder source. The source function receives (prompt, done)
--- where done(paths) must be called exactly once with a list of file paths.
--- Sources may call done synchronously or asynchronously.
function M.add_source(source)
  M.sources[#M.sources + 1] = source
end

local fd_cmd
local home
local recent_files = require("config.recent-files")

function M.find()
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local make_entry = require("telescope.make_entry")
  local action_state = require("telescope.actions.state")

  if not fd_cmd then
    fd_cmd = vim.fn.executable("fd") == 1 and "fd" or "fdfind"
    home = vim.env.HOME
  end

  local recent, recent_set = recent_files.get()
  local entry_maker = make_entry.gen_from_file({})

  local function make_finder(extra)
    if not extra or #extra == 0 then
      return finders.new_table({ results = recent, entry_maker = entry_maker })
    end
    local all = {}
    local seen = {}
    local n = 0
    for i = 1, #recent do
      n = n + 1
      all[n] = recent[i]
      seen[recent[i]] = true
    end
    for i = 1, #extra do
      local f = extra[i]
      if not seen[f] and not recent_set[f] then
        seen[f] = true
        n = n + 1
        all[n] = f
      end
    end
    return finders.new_table({ results = all, entry_maker = entry_maker })
  end

  -- Debounce typing so we don't fork fd on every keystroke.
  -- query_gen monotonically increments; stale callbacks discard their results.
  local debounce_timer = vim.uv.new_timer()
  local last_query = ""
  local active_procs = {}
  local query_gen = 0

  local function kill_active()
    for i = 1, #active_procs do
      pcall(active_procs[i].kill, active_procs[i], 9)
    end
    active_procs = {}
  end

  local function cleanup()
    debounce_timer:stop()
    if not debounce_timer:is_closing() then
      debounce_timer:close()
    end
    kill_active()
  end

  local picker = pickers.new({}, {
    prompt_title = "Files",
    initial_mode = "insert",
    finder = make_finder(),
    sorter = conf.file_sorter({}),
    previewer = conf.file_previewer({}),
    attach_mappings = function(prompt_bufnr)
      vim.api.nvim_create_autocmd("BufDelete", {
        buffer = prompt_bufnr,
        once = true,
        callback = cleanup,
      })

      vim.api.nvim_buf_attach(prompt_bufnr, false, {
        on_lines = function()
          debounce_timer:stop()
          debounce_timer:start(
            150,
            0,
            vim.schedule_wrap(function()
              if not vim.api.nvim_buf_is_valid(prompt_bufnr) then
                return
              end
              local current = action_state.get_current_picker(prompt_bufnr)
              if not current then
                return
              end
              local prompt = current:_get_prompt()
              if not prompt or #prompt < 2 or prompt == last_query then
                return
              end
              last_query = prompt

              kill_active()

              query_gen = query_gen + 1
              local my_gen = query_gen
              local extra = {}

              local n_sources = 1 + #M.sources
              local pending = n_sources

              local function on_complete()
                pending = pending - 1
                if pending > 0 then
                  return
                end
                if my_gen ~= query_gen then
                  return
                end
                if not vim.api.nvim_buf_is_valid(prompt_bufnr) then
                  return
                end
                local p = action_state.get_current_picker(prompt_bufnr)
                if p and #extra > 0 then
                  p:refresh(make_finder(extra), { reset_prompt = false })
                end
              end

              local function source_done(paths)
                if my_gen ~= query_gen then
                  on_complete()
                  return
                end
                if paths then
                  for i = 1, #paths do
                    if paths[i] ~= "" then
                      extra[#extra + 1] = paths[i]
                    end
                  end
                end
                on_complete()
              end

              -- Source 1: fd from HOME
              local fd_pattern = vim.fn.escape(prompt, "\\[](){}+?|^$"):gsub("%s+", ".*")
              local proc = vim.system({
                fd_cmd,
                "--type",
                "f",
                "--hidden",
                "--full-path",
                "--max-results",
                "50",
                "--",
                fd_pattern,
                home,
              }, { text = true }, function(result)
                local stdout = result.stdout or ""
                vim.schedule(function()
                  local parsed = {}
                  if stdout ~= "" then
                    for f in stdout:gmatch("[^\n]+") do
                      parsed[#parsed + 1] = f
                    end
                  end
                  source_done(parsed)
                end)
              end)
              active_procs[#active_procs + 1] = proc

              -- Source 2+: registered sources
              for _, source in ipairs(M.sources) do
                local called = false
                local function safe_done(paths)
                  if called then
                    return
                  end
                  called = true
                  source_done(paths)
                end
                local ok = pcall(source, prompt, safe_done)
                if not ok and not called then
                  on_complete()
                end
              end
            end)
          )
        end,
      })
      return true
    end,
  })

  picker:find()
end

return M
