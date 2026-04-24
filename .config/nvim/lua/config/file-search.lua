local M = {}

M.sources = {}

--- Register a search source. The source function receives (prompt, done)
--- where done(lines) must be called exactly once with vimgrep-format lines.
--- Sources may call done synchronously or asynchronously.
function M.add_source(source)
  M.sources[#M.sources + 1] = source
end

local home
local recent_files = require("config.recent-files")

function M.find()
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local make_entry = require("telescope.make_entry")
  local action_state = require("telescope.actions.state")

  if not home then
    home = vim.env.HOME
  end

  local entry_maker = make_entry.gen_from_vimgrep({})

  local function make_finder(results)
    return finders.new_table({
      results = results or {},
      entry_maker = entry_maker,
    })
  end

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

  local recent = recent_files.get()
  local tmpfile
  if #recent > 0 then
    tmpfile = vim.fn.tempname()
    vim.fn.writefile(recent, tmpfile)
  end

  local rg_base = { "rg", "--vimgrep", "--fixed-strings", "--smart-case", "--max-filesize", "1M" }

  local rg_recent_prefix
  if tmpfile then
    rg_recent_prefix = { unpack(rg_base) }
    local n = #rg_recent_prefix
    rg_recent_prefix[n + 1] = "--max-count"
    rg_recent_prefix[n + 2] = "3"
    rg_recent_prefix[n + 3] = "--files-from"
    rg_recent_prefix[n + 4] = tmpfile
    rg_recent_prefix[n + 5] = "--"
  end

  local rg_home_prefix = { unpack(rg_base) }
  local n = #rg_home_prefix
  rg_home_prefix[n + 1] = "--max-count"
  rg_home_prefix[n + 2] = "3"
  rg_home_prefix[n + 3] = "--max-depth"
  rg_home_prefix[n + 4] = "8"
  rg_home_prefix[n + 5] = "--max-columns"
  rg_home_prefix[n + 6] = "200"
  rg_home_prefix[n + 7] = "--max-columns-preview"
  rg_home_prefix[n + 8] = "--"

  local function cleanup()
    debounce_timer:stop()
    if not debounce_timer:is_closing() then
      debounce_timer:close()
    end
    kill_active()
    if tmpfile then
      vim.fn.delete(tmpfile)
      tmpfile = nil
    end
  end

  local picker = pickers.new({}, {
    prompt_title = "Search",
    initial_mode = "insert",
    finder = make_finder(),
    sorter = require("telescope.sorters").empty(),
    previewer = conf.grep_previewer({}),
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
            200,
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
              local results = {}
              local seen = {}

              local n_sources = (rg_recent_prefix and 1 or 0) + 1 + #M.sources
              local pending = n_sources

              local function dedup_add(line)
                local key = line:match("^(.-:%d+:)") or line
                if not seen[key] then
                  seen[key] = true
                  results[#results + 1] = line
                end
              end

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
                if p then
                  p:refresh(make_finder(results), { reset_prompt = false })
                end
              end

              local function source_done(lines)
                if my_gen ~= query_gen then
                  on_complete()
                  return
                end
                if lines then
                  for i = 1, #lines do
                    if lines[i] ~= "" then
                      dedup_add(lines[i])
                    end
                  end
                end
                on_complete()
              end

              -- Source 1: ripgrep on recent files
              if rg_recent_prefix then
                local cmd = { unpack(rg_recent_prefix) }
                cmd[#cmd + 1] = prompt
                local proc = vim.system(cmd, { text = true }, function(result)
                  local stdout = result.stdout or ""
                  vim.schedule(function()
                    local parsed = {}
                    if stdout ~= "" then
                      for line in stdout:gmatch("[^\n]+") do
                        parsed[#parsed + 1] = line
                      end
                    end
                    source_done(parsed)
                  end)
                end)
                active_procs[#active_procs + 1] = proc
              end

              -- Source 2: ripgrep from HOME
              local cmd2 = { unpack(rg_home_prefix) }
              cmd2[#cmd2 + 1] = prompt
              cmd2[#cmd2 + 1] = home
              local proc2 = vim.system(cmd2, { text = true }, function(result)
                local stdout = result.stdout or ""
                vim.schedule(function()
                  local parsed = {}
                  if stdout ~= "" then
                    local count = 0
                    for line in stdout:gmatch("[^\n]+") do
                      parsed[#parsed + 1] = line
                      count = count + 1
                      if count >= 200 then
                        break
                      end
                    end
                  end
                  source_done(parsed)
                end)
              end)
              active_procs[#active_procs + 1] = proc2

              -- Source 3+: registered sources
              -- Sources receive (prompt, done). done() must be called exactly
              -- once with a list of vimgrep-format lines. May be called
              -- synchronously or asynchronously (via vim.schedule).
              for _, source in ipairs(M.sources) do
                local called = false
                local function safe_done(lines)
                  if called then
                    return
                  end
                  called = true
                  source_done(lines)
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
