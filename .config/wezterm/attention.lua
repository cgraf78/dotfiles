-- Presentation only: tmux remains the authority for work and acknowledgement.
-- Read the bounded snapshots already attached to panes; never run commands from
-- the synchronous tab formatter, which executes on WezTerm's GUI thread.
local M = {}
local received = {}
local lifetime = 15
local notices = {}
local windows = {}
local frames = {}
local frame_interval = 0.15

--- Load the shared, single-cell Braille frames.
function M.setup_frames(path)
  frames = {}
  local file = io.open(path, "r")
  if file then
    local valid = true
    for frame in file:lines() do
      -- Frame text reaches the tab renderer; reject control and multi-cell
      -- input rather than letting a broken copy change tab layout.
      if not frame:match("^\226[\160-\163][\128-\191]$") then
        valid = false
        break
      end
      frames[#frames + 1] = frame
    end
    file:close()
    if not valid or #frames < 2 then
      frames = {}
    end
  end
end

local function work_mark(wezterm)
  if #frames < 2 or not wezterm.time or not wezterm.time.now then
    return "⋯"
  end
  local ok, value = pcall(function()
    return tonumber(wezterm.time.now():format("%s%3f"))
  end)
  if not ok or not value then
    return "⋯"
  end
  return frames[math.floor(value / (frame_interval * 1000)) % #frames + 1]
end

local function count(value)
  return type(value) == "number" and value >= 0 and value <= 100000 and value % 1 == 0
end

local function snapshot(wezterm, pane)
  local vars = pane and pane.user_vars
  local value = vars and vars.TERM_PANE_STATE
  if type(value) ~= "string" or #value > 1024 then
    return nil
  end
  -- A heartbeat changes the raw snapshot even when counts are unchanged.
  -- Measure reception on this machine, so SSH clock skew cannot prolong a
  -- disconnected session's badge. Expiry hides stale transport, not the
  -- authoritative pending mark that tmux will replay on reconnect.
  local now = os.time()
  local key = pane.pane_id or pane
  local previous = received[key]
  if not previous or previous.value ~= value then
    received[key] = { value = value, at = now, seen = now }
  elseif now < previous.at or now - previous.at > lifetime then
    previous.seen = now
    return nil
  else
    previous.seen = now
  end
  local ok, state = pcall(wezterm.json_parse, value)
  if not ok or type(state) ~= "table" or state.v ~= 1 then
    return nil
  end
  if
    not count(state.working)
    or not count(state.pending)
    or not count(state.failed)
    or state.failed > state.pending
  then
    return nil
  end
  return state
end

local function signals(wezterm, panes)
  local working, pending, failed = false, false, false
  for _, pane in ipairs(panes) do
    local state = snapshot(wezterm, pane)
    if state then
      working = working or state.working > 0
      pending = pending or state.pending > 0
      failed = failed or state.failed > 0
    end
  end
  return working, pending, failed
end

--- Format a tab, retaining stock indices and room for independent badges.
function M.format(wezterm, tab, config, max_width)
  config = config or {}
  local active = tab.active_pane or {}
  local title = tab.tab_title
  if type(title) ~= "string" or title == "" then
    title = active.title or ""
  end
  local working, pending, failed = signals(wezterm, tab.panes or { active })
  local prefix = ""
  if config.show_tab_index_in_tab_bar ~= false and type(tab.tab_index) == "number" then
    prefix = tostring(tab.tab_index + (config.tab_and_split_indices_are_zero_based and 0 or 1))
      .. ": "
  end
  local mark = working and work_mark(wezterm) or ""
  local work_text = working and (" " .. mark) or ""
  local alert_text = failed and " !" or (pending and " ●" or "")
  if type(max_width) == "number" then
    max_width = math.max(0, math.floor(max_width))
    local suffix_width = wezterm.column_width(work_text .. alert_text)
    if max_width <= suffix_width then
      -- Under severe crowding, retain the actionable badge before the title or
      -- index. Two cells can still show both work and attention without spaces.
      local compact = mark .. alert_text:gsub(" ", "")
      if max_width == 1 and alert_text ~= "" then
        compact = alert_text:sub(2)
      end
      return { { Text = wezterm.truncate_right(compact, max_width) } }
    end
    local available = max_width - suffix_width
    prefix = wezterm.truncate_right(prefix, available)
    local title_width = math.max(0, available - wezterm.column_width(prefix))
    if wezterm.column_width(title) > title_width then
      title = title_width > 1 and (wezterm.truncate_right(title, title_width - 1) .. "…")
        or wezterm.truncate_right(title, title_width)
    end
  end
  local result = { { Text = prefix .. title } }
  if working then
    result[#result + 1] = { Text = work_text }
  end
  if failed or pending then
    result[#result + 1] = { Foreground = { Color = failed and "#ff5370" or "#f78c6c" } }
    result[#result + 1] = { Text = alert_text }
  end
  return result
end

--- Ignore stable WezTerm's bell broadcasts to unrelated GUI windows.
function M.owns(window, pane)
  local ok, owned = pcall(function()
    return window:mux_window():window_id() == pane:tab():window():window_id()
  end)
  -- A pane may disappear before this asynchronous event is delivered.
  return ok and owned or false
end

local function record(window)
  local ok, id = pcall(function()
    return window:window_id()
  end)
  if not ok then
    return nil
  end
  if not windows[id] then
    windows[id] = { toggle = false }
  end
  windows[id].seen = os.time()
  return windows[id], id
end

local function publish(wezterm, window, state, id)
  local notice = notices[id]
  local text = notice and notice.message or ""
  local status = wezterm.format({ { Text = text } }) .. (state.toggle and "\x1b[0m" or "")
  -- Stable WezTerm re-arms its status timer only when a status is submitted.
  -- Sending the identical raw string schedules the next tick without rebuilding
  -- titles; omitting it entirely would stop expiry checks once PTYs went quiet.
  local ok = pcall(function()
    window:set_right_status(status)
  end)
  return ok
end

local function reconcile(wezterm, window, state, id, redraw)
  local ok, fingerprint, any_work = pcall(function()
    local parts = {}
    local working_any = false
    for _, tab in ipairs(window:mux_window():tabs()) do
      local panes = {}
      for _, pane in ipairs(tab:panes()) do
        panes[#panes + 1] = { pane_id = pane:pane_id(), user_vars = pane:get_user_vars() }
      end
      local working, pending, failed = signals(wezterm, panes)
      working_any = working_any or working
      parts[#parts + 1] = tostring(tab:tab_id())
        .. ":"
        .. (working and "1" or "0")
        .. (pending and "1" or "0")
        .. (failed and "1" or "0")
    end
    return table.concat(parts, ";"), working_any
  end)
  state.checked_at = os.time()
  if not ok then
    -- A pane can disappear halfway through this scan. Keep the last semantic
    -- fingerprint and re-arm stable WezTerm's timer so the next tick can heal.
    -- Stop the fast timer until a successful scan proves work still exists.
    state.active = false
    return publish(wezterm, window, state, id)
  end
  state.active = any_work
  if state.fingerprint ~= fingerprint or redraw then
    state.fingerprint = fingerprint
    -- Stable WezTerm has no window:invalidate(). Its status timer only emits a
    -- Lua event; identical right-status strings do not rebuild cached tab titles.
    -- Toggle a zero-column reset only when semantic badges change, composing it
    -- with our current notice so expiry needs neither visible text nor polling
    -- subprocesses. No task is acknowledged or title mutated by this refresh.
    state.toggle = not state.toggle
  end
  local published = publish(wezterm, window, state, id)
  -- Expiry is not eviction: forgetting an alive pane's old snapshot would
  -- make it look newly received after a long sleep and resurrect stale badges.
  -- Only the mux can prove a pane is gone. This lookup stays outside formatting.
  if wezterm.mux and wezterm.mux.get_pane then
    for pane_id in pairs(received) do
      if type(pane_id) == "number" then
        local found, pane = pcall(wezterm.mux.get_pane, pane_id)
        if found and not pane then
          received[pane_id] = nil
        end
      end
    end
  end
  local now = os.time()
  for window_id, item in pairs(windows) do
    if not notices[window_id] and now - item.seen > lifetime * 4 then
      windows[window_id] = nil
    end
  end
  return published
end

local function arm(wezterm, window, state, id)
  if state.timer or not state.active or #frames < 2 or not wezterm.time then
    return
  end
  state.timer = true
  local ok = pcall(wezterm.time.call_after, frame_interval, function()
    state.timer = false
    -- Reloaded configs and closed windows can leave a queued callback behind.
    -- Never touch a stale handle or schedule another timer from it.
    if
      wezterm.GLOBAL ~= nil
      and wezterm.GLOBAL["term_tab_spinner_window_" .. id] ~= state.token
    then
      return
    end
    if windows[id] ~= state or not state.active then
      return
    end
    local live, window_id = pcall(function()
      return window:window_id()
    end)
    if not live or window_id ~= id then
      return
    end
    state.seen = os.time()
    local now = os.time()
    local published
    if not state.checked_at or now < state.checked_at or now - state.checked_at >= 1 then
      published = reconcile(wezterm, window, state, id, true)
    else
      state.toggle = not state.toggle
      published = publish(wezterm, window, state, id)
    end
    if published then
      arm(wezterm, window, state, id)
    end
  end)
  if not ok then
    state.timer = false
  end
end

--- Recompute expiry even when a disconnected terminal emits no more output.
function M.update(wezterm, window)
  local state, id = record(window)
  if not state then
    return
  end
  if wezterm.GLOBAL ~= nil and not state.token then
    -- Validation can evaluate the config after its GUI evaluation. Claim a
    -- window only when its real status callback runs, not during config load.
    state.token = tostring({}) .. ":" .. wezterm.time.now():format("%s%9f")
    wezterm.GLOBAL["term_tab_spinner_window_" .. id] = state.token
  end
  if reconcile(wezterm, window, state, id, false) then
    arm(wezterm, window, state, id)
  end
end

--- Show actionable link feedback without relying on macOS toast delivery.
function M.notice(wezterm, window, message)
  local state, id = record(window)
  if not state then
    return
  end
  local notice_generation = { message = message }
  notices[id] = notice_generation
  publish(wezterm, window, state, id)
  wezterm.time.call_after(8, function()
    -- An older notice must not erase a newer one, or touch a closed window.
    if notices[id] == notice_generation then
      notices[id] = nil
      pcall(function()
        if window:window_id() == id then
          publish(wezterm, window, state, id)
        end
      end)
    end
  end)
end

return M
