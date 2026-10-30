-- Exercise the active WezTerm timer without a GUI or wall-clock sleeps.
return function(module_path, frames_path)
  local function check(condition, message)
    if not condition then
      error(message or "spinner assertion failed", 2)
    end
    return condition
  end
  local clock = os.time
  local seconds, milliseconds = 100, 100000
  rawset(os, "time", function()
    return seconds
  end)
  local timers, statuses = {}, {}
  local function characters(value)
    return value:gmatch("[%z\1-\127\194-\244][\128-\191]*")
  end
  local api = {
    GLOBAL = {},
    json_parse = function(value)
      if value == "work" then
        return { v = 1, working = 1, pending = 1, failed = 1 }
      end
      return { v = 1, working = 0, pending = 0, failed = 0 }
    end,
    time = {
      now = function()
        return {
          format = function(_, pattern)
            check(pattern == "%s%3f" or pattern == "%s%9f")
            return pattern == "%s%3f" and tostring(milliseconds) or tostring(milliseconds * 1000000)
          end,
        }
      end,
      call_after = function(delay, callback)
        check(delay >= 0.1 and delay <= 0.2)
        timers[#timers + 1] = callback
      end,
    },
    format = function(parts)
      return parts[1].Text
    end,
    column_width = function(value)
      local width = 0
      for _ in characters(value) do
        width = width + 1
      end
      return width
    end,
    truncate_right = function(value, width)
      local result = ""
      local cells = 0
      for character in characters(value) do
        if cells >= width then
          break
        end
        result = result .. character
        cells = cells + 1
      end
      return result
    end,
  }
  local source = { pane_id = 7, user_vars = { TERM_PANE_STATE = "work" } }
  local tab = { tab_title = "agent", tab_index = 0, active_pane = source }
  local pane = {
    pane_id = function()
      return 7
    end,
    get_user_vars = function()
      return source.user_vars
    end,
  }
  local mux_tab = {
    tab_id = function()
      return 1
    end,
    panes = function()
      return { pane }
    end,
  }
  local visible_tabs = { mux_tab }
  local window = {
    window_id = function()
      return 9
    end,
    mux_window = function()
      return {
        tabs = function()
          return visible_tabs
        end,
      }
    end,
    set_right_status = function(_, value)
      statuses[#statuses + 1] = value
    end,
  }
  local function label(attention, width)
    local text = ""
    for _, item in ipairs(attention.format(api, tab, {}, width)) do
      text = text .. (item.Text or "")
    end
    return text
  end
  local function tick(index)
    check(timers[index], "expected one pending callback")
    milliseconds = milliseconds + 150
    timers[index]()
  end
  local attention = dofile(module_path)
  attention.setup_frames(frames_path)
  local validation = dofile(module_path)
  validation.setup_frames(frames_path)
  local first = label(attention)
  check(first:sub(-2) == " !" and not first:find("⋯", 1, true), "work frame missing")
  check(
    label(attention, 2):sub(-1) == "!" and not label(attention, 2):find("⋯", 1, true),
    "narrow tab lost a badge"
  )
  check(label(attention, 1) == "!", "one-cell tab lost failed badge")
  attention.update(api, window)
  attention.update(api, window)
  check(#timers == 1, "duplicate fast timer")
  local status_count = #statuses
  tick(1)
  check(label(attention) ~= first, "frame did not advance")
  check(#statuses > status_count and #timers == 2, "timer did not redraw and rearm")
  local read_vars = pane.get_user_vars
  pane.get_user_vars = function()
    error("pane disappeared during scan")
  end
  seconds = 101
  tick(2)
  check(#timers == 2, "failed scan kept a fast timer")
  pane.get_user_vars = read_vars
  attention.update(api, window)
  check(#timers == 3, "healthy scan did not restart timer")
  seconds = 116
  tick(3)
  check(#timers == 3, "expired work kept a fast timer")
  check(label(attention) == "1: agent", "expired work remained visible")
  source.user_vars.TERM_PANE_STATE = "idle"
  seconds = 117
  attention.update(api, window)
  check(#timers == 3, "idle pane started a timer")
  source.user_vars.TERM_PANE_STATE = "work-new"
  api.json_parse = function(value)
    return { v = 1, working = value == "work-new" and 1 or 0, pending = 0, failed = 0 }
  end
  attention.update(api, window)
  check(#timers == 4, "fresh work did not restart timer")
  visible_tabs = {}
  seconds = 118
  tick(4)
  check(#timers == 4, "vanished tab kept fast timer")
  visible_tabs = { mux_tab }
  attention.update(api, window)
  check(#timers == 5)
  local new = dofile(module_path)
  new.setup_frames(frames_path)
  new.update(api, window)
  check(#timers == 6)
  local before = #statuses
  tick(5)
  check(#statuses == before and #timers == 6, "old config callback survived reload")
  window.window_id = function()
    error("window closed")
  end
  tick(6)
  check(#timers == 6, "closed window kept fast timer")

  local missing = dofile(module_path)
  missing.setup_frames(frames_path .. ".missing")
  check(label(missing):find("⋯", 1, true), "missing frames lost static fallback")
  local invalid = os.tmpname()
  local handle = check(io.open(invalid, "w"))
  handle:write("⠋ ; kill-server\n⠙\n")
  handle:close()
  local bad = dofile(module_path)
  bad.setup_frames(invalid)
  os.remove(invalid)
  check(label(bad):find("⋯", 1, true), "invalid frames were accepted")
  rawset(os, "time", clock)
  print("spinner-timers-and-fallbacks-ok")
end
