local wezterm = require("wezterm")
local act = wezterm.action

local target = wezterm.target_triple or ""
local is_macos = target:find("darwin", 1, true) ~= nil
local is_windows = target:find("windows", 1, true) ~= nil
local is_linux = target:find("linux", 1, true) ~= nil

local function file_exists(path)
  local ok, _, code = os.rename(path, path)
  if ok then
    return true
  end

  return code == 13 -- Permission denied still means the path exists.
end

local function first_existing(paths)
  for _, path in ipairs(paths) do
    if file_exists(path) then
      return path
    end
  end

  return nil
end

local function font_with_fallback(names)
  return wezterm.font_with_fallback(names)
end

local function bind(key, mods, action)
  return {
    key = key,
    mods = mods,
    action = action,
  }
end

local function append_all(dst, src)
  for _, item in ipairs(src) do
    table.insert(dst, item)
  end
end

local function copy_or_interrupt(window, pane)
  local selection = window:get_selection_text_for_pane(pane)
  if selection and selection ~= "" then
    window:perform_action(act.CopyTo("Clipboard"), pane)
    window:perform_action(act.ClearSelection, pane)
  else
    window:perform_action(act.SendKey({ key = "c", mods = "CTRL" }), pane)
  end
end

local function prompt_rename_tab(window, pane)
  window:perform_action(
    act.PromptInputLine({
      description = "Rename current tab",
      action = wezterm.action_callback(function(inner_window, _, line)
        if line ~= nil then
          inner_window:active_tab():set_title(line)
        end
      end),
    }),
    pane
  )
end

local font_names = {
  { family = "JetBrainsMono Nerd Font", weight = "Light" },
  "FiraCode Nerd Font",
  "MesloLGM Nerd Font Mono",
}
local font_size
local line_height
local default_prog
local window_decorations = "TITLE|RESIZE"
local macos_window_background_blur = 0
local front_end
local freetype_load_target
local freetype_render_target

if is_macos then
  table.insert(font_names, "Menlo")
  font_size = 11
  line_height = 1.0

  -- Use the system login shell (set via chsh).
  default_prog = nil

  macos_window_background_blur = 18

  -- Sharper glyph rendering on external (non-Retina) displays like the Dell.
  -- WebGpu uses Metal and is crisper than the default OpenGL front end on
  -- macOS. Grayscale Light render target avoids the subpixel color-fringing
  -- that reads as perceived-bold text on lower-PPI external panels.
  front_end = "WebGpu"
  freetype_load_target = "Light"
  freetype_render_target = "Light"
elseif is_windows then
  table.insert(font_names, "Consolas")
  font_size = 9.0
  line_height = 1.0
  -- WSL needs an explicit program; can't use the login shell.
  default_prog = { "wsl.exe", "-d", "archlinux", "--cd", "/home/chris", "--exec", "/bin/zsh", "-l" }
elseif is_linux then
  table.insert(font_names, "DejaVu Sans Mono")
  font_size = 9.5
  line_height = 1.0
else
  table.insert(font_names, "monospace")
  font_size = 10.0
  line_height = 1.0
end

local keys = {
  -- Shift+Enter: send CSI u sequence (kitty keyboard protocol) so TUIs can
  -- distinguish it from plain Enter. Requires tmux extended-keys passthrough
  -- (set via terminal-features extkeys in tmux.conf).
  bind("Enter", "SHIFT", act.SendString("\x1b[13;2u")),

  -- Pass Shift-PageUp/Down to the application (overrides WezTerm scrollback)
  bind("PageUp", "SHIFT", act.SendString("\x1b[5;2~")),
  bind("PageDown", "SHIFT", act.SendString("\x1b[6;2~")),
  bind("PageUp", "CTRL|SHIFT", act.SendString("\x1b[5;6~")),
  bind("PageDown", "CTRL|SHIFT", act.SendString("\x1b[6;6~")),

  -- Font size controls
  bind("=", "CTRL", act.IncreaseFontSize),
  bind("-", "CTRL", act.DecreaseFontSize),
  bind("0", "CTRL", act.ResetFontSize),

  -- Clipboard
  bind("c", "CTRL", wezterm.action_callback(copy_or_interrupt)),
  bind("c", "CTRL|SHIFT", act.CopyTo("Clipboard")),
  bind("v", "CTRL", act.PasteFrom("Clipboard")),
  bind("v", "CTRL|SHIFT", act.PasteFrom("Clipboard")),

  -- Tabs / windows
  bind("t", "CTRL", act.SpawnTab("DefaultDomain")),
  bind("t", "CTRL|SHIFT", act.SpawnTab("DefaultDomain")),
  bind("w", "CTRL|SHIFT", act.CloseCurrentTab({ confirm = false })),
  bind("Tab", "CTRL", act.ActivateTabRelative(1)),
  bind("Tab", "CTRL|SHIFT", act.ActivateTabRelative(-1)),
  bind("{", "CTRL", act.ActivateTabRelative(-1)),
  bind("}", "CTRL", act.ActivateTabRelative(1)),
  bind("{", "ALT|SHIFT", act.MoveTabRelative(-1)),
  bind("}", "ALT|SHIFT", act.MoveTabRelative(1)),

  -- Search / launcher
  bind("g", "CTRL", act.CopyMode("NextMatch")),
  bind("g", "CTRL|SHIFT", act.CopyMode("PriorMatch")),
  bind("p", "CTRL|SHIFT", act.ActivateCommandPalette),
  bind("r", "CTRL|SHIFT", wezterm.action_callback(prompt_rename_tab)),

  -- Alt-number tab switching
  bind("1", "ALT", act.ActivateTab(0)),
  bind("2", "ALT", act.ActivateTab(1)),
  bind("3", "ALT", act.ActivateTab(2)),
  bind("4", "ALT", act.ActivateTab(3)),
}

if is_macos then
  append_all(keys, {
    -- Native-feeling macOS aliases mirroring the cross-platform Ctrl bindings.
    bind("=", "SUPER", act.IncreaseFontSize),
    bind("-", "SUPER", act.DecreaseFontSize),
    bind("0", "SUPER", act.ResetFontSize),
    bind("c", "SUPER", act.CopyTo("Clipboard")),
    bind("v", "SUPER", act.PasteFrom("Clipboard")),
    bind("t", "SUPER", act.SpawnTab("DefaultDomain")),
    bind("T", "SUPER", act.SpawnTab("DefaultDomain")),
    bind("w", "SUPER", act.CloseCurrentTab({ confirm = false })),
    bind("W", "SUPER", act.CloseCurrentTab({ confirm = false })),
    bind("f", "SUPER", act.Search({ CaseSensitiveString = "" })),
    bind("g", "SUPER", act.CopyMode("NextMatch")),
    bind("g", "SUPER|SHIFT", act.CopyMode("PriorMatch")),
    bind("n", "SUPER", act.SpawnWindow),
    bind("p", "SUPER|SHIFT", act.ActivateCommandPalette),
    bind("r", "SUPER|SHIFT", wezterm.action_callback(prompt_rename_tab)),
    bind("Tab", "SUPER", act.ActivateTabRelative(1)),
    bind("Tab", "SUPER|SHIFT", act.ActivateTabRelative(-1)),
    bind("[", "SUPER|SHIFT", act.ActivateTabRelative(-1)),
    bind("]", "SUPER|SHIFT", act.ActivateTabRelative(1)),

    -- OPT+arrows: word jump (common in iTerm2/Terminal.app)
    bind("LeftArrow", "OPT", act.SendString("\x1bb")),
    bind("RightArrow", "OPT", act.SendString("\x1bf")),

    -- CTRL+arrows: send xterm modifier sequences for word navigation.
    -- Works correctly in bash/readline and vim. Requires a fresh tmux session
    -- (not just tmux source) to take effect inside tmux.
    bind("LeftArrow", "CTRL", act.SendString("\x1b[1;5D")),
    bind("RightArrow", "CTRL", act.SendString("\x1b[1;5C")),
    bind("LeftArrow", "CTRL|SHIFT", act.SendString("\x1b[1;6D")),
    bind("RightArrow", "CTRL|SHIFT", act.SendString("\x1b[1;6C")),
  })
end

-- =============================================================================
-- File-path hyperlinks → open in nvim via tmux
-- =============================================================================
wezterm.on("open-uri", function(window, pane, uri)
  local path_info = uri:match("^nvim%-open://(.+)$")
  if not path_info then
    return true
  end

  if is_linux then
    wezterm.background_child_process({
      os.getenv("HOME") .. "/.local/bin/nvim-tmux-open",
      path_info,
    })
  else
    -- Send raw \x02 byte (Ctrl-B = tmux prefix). `SendKey` with CTRL
    -- encodes as CSI-u under kitty keyboard protocol, which tmux may
    -- not map back to the prefix; a literal byte avoids that.
    window:perform_action(
      act.SendString("\x02:run-shell 'nvim-tmux-open " .. path_info .. "'\r"),
      pane
    )
  end
  return false
end)

-- =============================================================================
-- Terminal notification: play Glass sound via OSC 1337 user var
-- =============================================================================
wezterm.on("user-var-changed", function(window, pane, name, value)
  if name == "term_notify" and value == "1" then
    if is_macos then
      wezterm.background_child_process({ "afplay", "/System/Library/Sounds/Glass.aiff" })
    elseif is_linux then
      wezterm.background_child_process({ "paplay", "/usr/share/sounds/freedesktop/stereo/bell.oga" })
    end
  elseif name == "term_open_url" and value ~= "" then
    wezterm.open_with(value)
  end
end)

-- =============================================================================
-- Config
-- =============================================================================
return {
  default_prog = default_prog,

  color_scheme = "Tokyo Night",

  colors = {
    foreground = "#e6e9ef",
    ansi = {
      "#15161e",
      "#f7768e",
      "#55c26a",
      "#e0af68",
      "#7aa2f7",
      "#bb9af7",
      "#7dcfff",
      "#c0caf5",
    },
    brights = {
      "#414868",
      "#f7768e",
      "#6fe287",
      "#e0af68",
      "#7aa2f7",
      "#bb9af7",
      "#7dcfff",
      "#e6e9ef",
    },
    tab_bar = {
      inactive_tab = {
        bg_color = "#24283b",
        fg_color = "#565f89",
      },
      active_tab = {
        bg_color = "#1a1b26",
        fg_color = "#c0caf5",
      },
      new_tab = {
        bg_color = "#24283b",
        fg_color = "#565f89",
      },
    },
  },

  -- Appearance
  font = font_with_fallback(font_names),
  font_size = font_size,
  line_height = line_height,
  front_end = front_end,
  freetype_load_target = freetype_load_target,
  freetype_render_target = freetype_render_target,
  enable_scroll_bar = false,
  hide_tab_bar_if_only_one_tab = true,
  initial_cols = 140,
  initial_rows = 36,
  use_fancy_tab_bar = true,
  tab_bar_at_bottom = false,
  window_frame = {
    font_size = 13.0,
    active_titlebar_bg = "#1a1b26",
    inactive_titlebar_bg = "#1a1b26",
  },
  window_padding = {
    left = 6,
    right = 6,
    top = 6,
    bottom = 6,
  },
  adjust_window_size_when_changing_font_size = false,
  window_close_confirmation = "NeverPrompt",
  window_decorations = window_decorations,
  macos_window_background_blur = macos_window_background_blur,

  -- Behavior
  -- SUPER (CMD) bypasses tmux mouse reporting so CMD+Click opens links.
  bypass_mouse_reporting_modifiers = "SUPER",
  scrollback_lines = 20000,
  check_for_updates = false,
  automatically_reload_config = true,
  swallow_mouse_click_on_window_focus = true,
  audible_bell = "SystemBeep",
  default_cursor_style = "SteadyBar",

  keys = keys,

  mouse_bindings = {
    -- CMD+Click opens hyperlinks on macOS.
    {
      event = { Up = { streak = 1, button = "Left" } },
      mods = "SUPER",
      action = act.OpenLinkAtMouseCursor,
    },
  },

  -- Keep hyperlinks useful in terminal output.
  hyperlink_rules = (function()
    local rules = wezterm.default_hyperlink_rules()

    -- Absolute file paths with optional :line:col
    table.insert(rules, {
      regex = [[(/[^\s:]+\.\w+(?::\d+){0,2})(?=\s|$|[,;)\]}>])]],
      format = "nvim-open://$1",
    })

    -- Relative file paths (must contain /) with optional :line:col
    table.insert(rules, {
      regex = [[(?:^|(?<=\s))([\w@.-]+/[^\s:]+\.\w+(?::\d+){0,2})(?=\s|$|[,;)\]}>])]],
      format = "nvim-open://$1",
    })

    return rules
  end)(),
}
