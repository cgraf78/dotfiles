-- Presentation only: tmux remains the authority for work and acknowledgement.
-- Read the bounded snapshots already attached to panes; never run commands from
-- the synchronous tab formatter, which executes on WezTerm's GUI thread.
local M = {}
local received = {}
local lifetime = 15
local notices = {}
local windows = {}
-- Dots, most severe first, in the colors the tmux tabs use.
local dots = {
  { key = "failed", color = "#ff5370" },
  { key = "waiting", color = "#ffcb6b" },
  { key = "done", color = "#addb67" },
  { key = "working", color = "#82aaff" },
}

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
  -- Publishers count each pane once by its effective state: red (failed),
  -- yellow (waiting) and green (the rest) partition pending, and working
  -- counts only panes with no attention. Older publishers send no waiting.
  local waiting = state.waiting
  if waiting == nil then
    waiting = 0
  end
  if
    not count(state.working)
    or not count(state.pending)
    or not count(state.failed)
    or not count(waiting)
    or state.failed + waiting > state.pending
  then
    return nil
  end
  return {
    failed = state.failed,
    waiting = waiting,
    done = state.pending - state.failed - waiting,
    working = state.working,
  }
end

local function signals(wezterm, panes)
  local present = { failed = false, waiting = false, done = false, working = false }
  for _, pane in ipairs(panes) do
    local state = snapshot(wezterm, pane)
    if state then
      for _, dot in ipairs(dots) do
        present[dot.key] = present[dot.key] or state[dot.key] > 0
      end
    end
  end
  return present
end

--- Format a tab, retaining stock indices and room for independent badges.
function M.format(wezterm, tab, config, max_width)
  config = config or {}
  local active = tab.active_pane or {}
  local title = tab.tab_title
  if type(title) ~= "string" or title == "" then
    title = active.title or ""
  end
  local present = signals(wezterm, tab.panes or { active })
  local shown = {}
  for _, dot in ipairs(dots) do
    if present[dot.key] then
      shown[#shown + 1] = dot
    end
  end
  local prefix = ""
  if config.show_tab_index_in_tab_bar ~= false and type(tab.tab_index) == "number" then
    prefix = tostring(tab.tab_index + (config.tab_and_split_indices_are_zero_based and 0 or 1))
      .. ": "
  end
  local gap = #shown > 0 and " " or ""
  if type(max_width) == "number" then
    max_width = math.max(0, math.floor(max_width))
    local suffix_width = wezterm.column_width(gap .. string.rep("●", #shown))
    if max_width <= suffix_width then
      -- Under severe crowding, keep the dots before the title or index, the
      -- most severe ones first, since they are what needs you.
      local result = {}
      for index = 1, math.min(max_width, #shown) do
        result[#result + 1] = { Foreground = { Color = shown[index].color } }
        result[#result + 1] = { Text = "●" }
      end
      if #result == 0 then
        result[1] = { Text = "" }
      end
      return result
    end
    local available = max_width - suffix_width
    prefix = wezterm.truncate_right(prefix, available)
    local title_width = math.max(0, available - wezterm.column_width(prefix))
    if wezterm.column_width(title) > title_width then
      title = title_width > 1 and (wezterm.truncate_right(title, title_width - 1) .. "…")
        or wezterm.truncate_right(title, title_width)
    end
  end
  local result = { { Text = prefix .. title .. gap } }
  for _, dot in ipairs(shown) do
    result[#result + 1] = { Foreground = { Color = dot.color } }
    result[#result + 1] = { Text = "●" }
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
  pcall(function()
    window:set_right_status(status)
  end)
end

--- Recompute expiry even when a disconnected terminal emits no more output.
function M.update(wezterm, window)
  local state, id = record(window)
  if not state then
    return
  end
  if not state.spinner_retired then
    -- Configs with the retired working spinner chained a 150 ms redraw timer
    -- per window that survives a config reload while this shared token still
    -- matches. Replace the token so a queued chain stops at its next tick.
    state.spinner_retired = true
    pcall(function()
      local key = "term_tab_spinner_window_" .. id
      if wezterm.GLOBAL ~= nil and wezterm.GLOBAL[key] ~= nil then
        wezterm.GLOBAL[key] = "retired"
      end
    end)
  end
  local ok, fingerprint = pcall(function()
    local parts = {}
    for _, tab in ipairs(window:mux_window():tabs()) do
      local panes = {}
      for _, pane in ipairs(tab:panes()) do
        panes[#panes + 1] = { pane_id = pane:pane_id(), user_vars = pane:get_user_vars() }
      end
      local present = signals(wezterm, panes)
      local part = tostring(tab:tab_id()) .. ":"
      for _, dot in ipairs(dots) do
        part = part .. (present[dot.key] and "1" or "0")
      end
      parts[#parts + 1] = part
    end
    return table.concat(parts, ";")
  end)
  if not ok then
    -- A pane can disappear halfway through this scan. Keep the last semantic
    -- fingerprint and re-arm stable WezTerm's timer so the next tick can heal.
    publish(wezterm, window, state, id)
    return
  end
  if state.fingerprint ~= fingerprint then
    state.fingerprint = fingerprint
    -- Stable WezTerm has no window:invalidate(). Its status timer only emits a
    -- Lua event; identical right-status strings do not rebuild cached tab titles.
    -- Toggle a zero-column reset only when semantic dots change, composing it
    -- with our current notice so expiry needs neither visible text nor polling
    -- subprocesses. No task is acknowledged or title mutated by this refresh.
    state.toggle = not state.toggle
  end
  publish(wezterm, window, state, id)
  -- Expiry is not eviction: forgetting an alive pane's old snapshot would
  -- make it look newly received after a long sleep and resurrect stale dots.
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
