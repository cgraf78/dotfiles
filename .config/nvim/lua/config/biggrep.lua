-- biggrep.lua — Telescope picker for Meta's BigGrep code search.
--
-- Usage:
--   :BigGrep [corpus]          prompt for query, search corpus (default: xbgs)
--   :BigGrep xbgs MyClass      search immediately
--   :BigGrepWord [corpus]      search word under cursor
--
-- Flow:
--   1. Enter search query (the text to grep for)
--   2. Telescope opens — type in the prompt to filter by file path
--      (sends -f to BigGrep server-side, re-queries on each change)
--   3. Select a result to jump to that file:line
--
-- From the results picker:
--   <CR>   open file      <C-v> vertical split    <C-x> horizontal split
--   <C-t>  new tab        <C-q> send to quickfix

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local sorters = require("telescope.sorters")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local entry_display = require("telescope.pickers.entry_display")

local M = {}

--- Known repo roots on this machine (first match wins).
local repo_roots = {
  vim.env.HOME .. "/fbsource",
  "/data/users/" .. (vim.env.USER or "") .. "/fbsource",
}

--- Strip the repo prefix (e.g. "fbsource/") from a BigGrep path and resolve
--- it to a local absolute path if the checkout exists.
local function resolve_path(bg_path)
  local repo, rel = bg_path:match("^([^/]+)/(.+)$")
  if not repo then
    return bg_path
  end
  for _, root in ipairs(repo_roots) do
    if root:match(repo .. "$") then
      local abs = root .. "/" .. rel
      if vim.fn.filereadable(abs) == 1 then
        return abs
      end
    end
  end
  return bg_path
end

--- Parse a BigGrep output line: "repo/path:line:col:content"
local function parse_line(line)
  local path, lnum, col, text = line:match("^(.+):(%d+):(%d+):(.*)$")
  if not path then
    path, lnum, text = line:match("^(.+):(%d+):(.*)$")
    col = "1"
  end
  if not path then
    return nil
  end
  return {
    path = path,
    abs_path = resolve_path(path),
    lnum = tonumber(lnum),
    col = tonumber(col) or 1,
    text = vim.trim(text or ""),
  }
end

--- Default corpus when none specified.
local default_corpus = "xbgs"

--- Available corpora for tab-completion.
local corpora = {
  "xbgs", "fbgs", "tbgs", "zbgs", "obgs",
  "xbgr", "fbgr", "tbgr",
  "xbgf", "fbgf", "tbgf",
}

--- Last-used path filter, pre-filled on next search.
local last_path_filter = ""

local displayer = entry_display.create({
  separator = " ",
  items = {
    { remaining = true },
    { remaining = true },
  },
})

local function make_entry(line)
  if line:match("^More results") then
    return nil
  end
  local parsed = parse_line(line)
  if not parsed then
    return nil
  end
  local short = parsed.path:gsub("^fbsource/", "")
  return {
    value = parsed,
    display = function()
      return displayer({
        { short .. ":" .. parsed.lnum, "TelescopeResultsIdentifier" },
        { parsed.text, "TelescopeResultsComment" },
      })
    end,
    ordinal = short .. " " .. parsed.text,
    filename = parsed.abs_path,
    lnum = parsed.lnum,
    col = parsed.col,
  }
end

--- A sorter that passes everything through (no filtering/reordering).
--- We handle filtering server-side via BigGrep's -f flag.
local function passthrough_sorter()
  return sorters.new({
    scoring_function = function()
      return 0
    end,
  })
end

--- Run BigGrep and show results in Telescope.
--- The Telescope prompt filters by file path (sent as -f to BigGrep).
function M.search(opts)
  opts = opts or {}
  local corpus = opts.corpus or default_corpus
  local query = opts.query
  local limit = tostring(opts.limit or 1000)

  if not query or query == "" then
    vim.ui.input({ prompt = corpus .. ": " }, function(input)
      if input and input ~= "" then
        M.search(vim.tbl_extend("force", opts, { query = input }))
      end
    end)
    return
  end

  local function build_cmd(path_filter)
    local cmd = { corpus, "-n", limit }
    if path_filter and path_filter ~= "" then
      table.insert(cmd, "-f")
      table.insert(cmd, path_filter)
    end
    if opts.ignore_case then
      table.insert(cmd, "-i")
    end
    table.insert(cmd, query)
    return cmd
  end

  -- State for debouncing and async jobs
  local debounce_timer = nil
  local debounce_ms = 500
  local active_job = nil
  local picker_ref = nil
  local picker_closed = false
  local last_prompt = last_path_filter
  local query_generation = 0

  local function run_query(path_filter)
    -- Cancel in-flight job
    if active_job then
      vim.fn.jobstop(active_job)
      active_job = nil
    end

    query_generation = query_generation + 1
    local my_generation = query_generation
    local cmd = build_cmd(path_filter)
    local lines = {}

    active_job = vim.fn.jobstart(cmd, {
      stdout_buffered = true,
      on_stdout = function(_, data)
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(lines, line)
          end
        end
      end,
      on_exit = function()
        active_job = nil
        vim.schedule(function()
          -- Discard if picker closed or a newer query superseded us
          if picker_closed or my_generation ~= query_generation then
            return
          end
          if not picker_ref or not picker_ref.manager then
            return
          end
          local entries = {}
          for _, line in ipairs(lines) do
            local entry = make_entry(line)
            if entry then
              table.insert(entries, entry)
            end
          end
          picker_ref:refresh(
            finders.new_table({
              results = entries,
              entry_maker = function(e) return e end,
            }),
            { reset_prompt = false }
          )
        end)
      end,
    })
  end

  -- Run initial query synchronously so picker opens with data
  local initial_cmd = build_cmd(last_path_filter)
  local initial_lines = vim.fn.systemlist(initial_cmd)
  local initial_entries = {}
  for _, line in ipairs(initial_lines) do
    local entry = make_entry(line)
    if entry then
      table.insert(initial_entries, entry)
    end
  end

  local picker = pickers.new({}, {
    prompt_title = corpus .. ": " .. query .. "  (type to filter by path)",
    default_text = last_path_filter,
    finder = finders.new_table({
      results = initial_entries,
      entry_maker = function(e) return e end,
    }),
    previewer = conf.grep_previewer({}),
    sorter = passthrough_sorter(),
    layout_strategy = "vertical",
    layout_config = {
      vertical = {
        mirror = true,
        preview_height = 0.45,
        prompt_position = "top",
      },
    },
    attach_mappings = function(prompt_bufnr, map)
      -- Watch for prompt changes to re-query BigGrep
      vim.api.nvim_create_autocmd("TextChangedI", {
        buffer = prompt_bufnr,
        callback = function()
          if picker_closed then
            return true -- remove autocmd
          end
          -- Only re-query if we're actually in the prompt (not navigating results)
          if vim.api.nvim_get_current_buf() ~= prompt_bufnr then
            return
          end
          local current_prompt = action_state.get_current_line()
          if current_prompt == last_prompt then
            return
          end
          last_prompt = current_prompt

          if current_prompt ~= "" then
            last_path_filter = current_prompt
          end

          -- Debounce
          if debounce_timer then
            debounce_timer:stop()
          end
          debounce_timer = vim.uv.new_timer()
          debounce_timer:start(debounce_ms, 0, vim.schedule_wrap(function()
            if not picker_closed then
              run_query(current_prompt)
            end
          end))
        end,
      })

      local function close_picker()
        picker_closed = true
        if debounce_timer then
          debounce_timer:stop()
        end
        if active_job then
          vim.fn.jobstop(active_job)
          active_job = nil
        end
        actions.close(prompt_bufnr)
      end

      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        close_picker()
        if entry then
          vim.cmd("edit " .. vim.fn.fnameescape(entry.filename))
          vim.api.nvim_win_set_cursor(0, { entry.lnum, math.max(0, entry.col - 1) })
          vim.cmd("normal! zz")
        end
      end)

      map("i", "<Esc>", function() close_picker() end)
      map("n", "<Esc>", function() close_picker() end)
      map("n", "q", function() close_picker() end)

      return true
    end,
  })

  picker_ref = picker
  picker:find()
end

--- Search for the word under the cursor.
function M.search_word(opts)
  opts = opts or {}
  local word = vim.fn.expand("<cword>")
  if word == "" then
    vim.notify("No word under cursor", vim.log.levels.WARN)
    return
  end
  M.search(vim.tbl_extend("force", opts, { query = word }))
end

--- Command completion: return corpus names.
local function complete(_, cmd_line, _)
  local args = vim.split(cmd_line, "%s+")
  if #args <= 2 then
    return corpora
  end
  return {}
end

--- Parse flags (-f, -i) and positional args from command args.
local function parse_args(args)
  local opts = {}
  local positional = {}
  local i = 1
  while i <= #args do
    if args[i] == "-f" and args[i + 1] then
      opts.path_filter = args[i + 1]
      i = i + 2
    elseif args[i] == "-i" then
      opts.ignore_case = true
      i = i + 1
    else
      table.insert(positional, args[i])
      i = i + 1
    end
  end
  if #positional > 0 and vim.tbl_contains(corpora, positional[1]) then
    opts.corpus = table.remove(positional, 1)
  end
  if #positional > 0 then
    opts.query = table.concat(positional, " ")
  end
  return opts
end

vim.api.nvim_create_user_command("BigGrep", function(cmd)
  local args = vim.split(vim.trim(cmd.args), "%s+", { trimempty = true })
  M.search(parse_args(args))
end, { nargs = "*", complete = complete, desc = "BigGrep code search" })

vim.api.nvim_create_user_command("BigGrepWord", function(cmd)
  local args = vim.split(vim.trim(cmd.args), "%s+", { trimempty = true })
  local corpus = args[1]
  if corpus and not vim.tbl_contains(corpora, corpus) then
    corpus = nil
  end
  M.search_word({ corpus = corpus })
end, { nargs = "?", complete = complete, desc = "BigGrep word under cursor" })

return M
