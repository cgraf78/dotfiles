local wezterm = require 'wezterm'
local act = wezterm.action

local target = wezterm.target_triple or ''
local is_macos = target:find('darwin', 1, true) ~= nil
local is_windows = target:find('windows', 1, true) ~= nil
local is_linux = target:find('linux', 1, true) ~= nil

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

local font_names
local font_size
local line_height
local default_prog
local window_decorations = 'RESIZE'
local macos_window_background_blur = 0

if is_macos then
  font_names = {
    'JetBrains Mono',
    'Menlo',
    'Monaco',
    'SF Mono',
  }
  font_size = 10.5
  line_height = 1.05

  local bash_path = first_existing({
    '/opt/homebrew/bin/bash',
    '/usr/local/bin/bash',
    '/bin/bash',
  }) or '/bin/bash'
  default_prog = { bash_path, '-l' }

  window_decorations = 'TITLE|RESIZE'
  macos_window_background_blur = 18
elseif is_windows then
  font_names = {
    'Consolas',
    'Cascadia Mono',
    'JetBrains Mono',
  }
  font_size = 9.0
  line_height = 1.0
  default_prog = { 'wsl.exe', '-d', 'archlinux', '--cd', '/home/chris', '--exec', '/bin/bash', '-l' }
elseif is_linux then
  font_names = {
    'JetBrains Mono',
    'Cascadia Mono',
    'DejaVu Sans Mono',
    'Noto Sans Mono',
  }
  font_size = 9.5
  line_height = 1.0
  default_prog = { '/bin/bash', '-l' }
else
  font_names = {
    'JetBrains Mono',
    'Menlo',
    'Consolas',
    'DejaVu Sans Mono',
  }
  font_size = 10.0
  line_height = 1.0
  default_prog = { '/bin/bash', '-l' }
end

return {
  default_prog = default_prog,

  -- Appearance
  font = font_with_fallback(font_names),
  font_size = font_size,
  line_height = line_height,
  color_scheme = 'Tokyo Night',
  colors = {
    foreground = '#e6e9ef',
    ansi = {
      '#15161e',
      '#f7768e',
      '#55c26a',
      '#e0af68',
      '#7aa2f7',
      '#bb9af7',
      '#7dcfff',
      '#c0caf5',
    },
    brights = {
      '#414868',
      '#f7768e',
      '#6fe287',
      '#e0af68',
      '#7aa2f7',
      '#bb9af7',
      '#7dcfff',
      '#e6e9ef',
    },
  },
  enable_scroll_bar = false,
  hide_tab_bar_if_only_one_tab = true,
  initial_cols = 140,
  initial_rows = 36,
  use_fancy_tab_bar = false,
  tab_bar_at_bottom = false,
  window_padding = {
    left = 6,
    right = 6,
    top = 6,
    bottom = 6,
  },
  adjust_window_size_when_changing_font_size = false,
  window_close_confirmation = 'NeverPrompt',
  window_decorations = window_decorations,
  macos_window_background_blur = macos_window_background_blur,

  -- Behavior
  scrollback_lines = 20000,
  check_for_updates = false,
  automatically_reload_config = true,
  audible_bell = 'Disabled',
  default_cursor_style = 'SteadyBar',

  keys = {
    -- Try to make Shift+Enter distinct from plain Enter for TUIs.
    {
      key = 'Enter',
      mods = 'SHIFT',
      action = act.SendString('\x0a'),
    },

    -- Font size controls
    { key = '=', mods = 'CTRL', action = act.IncreaseFontSize },
    { key = '-', mods = 'CTRL', action = act.DecreaseFontSize },
    { key = '0', mods = 'CTRL', action = act.ResetFontSize },

    -- Clipboard
    { key = 'c', mods = 'CTRL|SHIFT', action = act.CopyTo('Clipboard') },
    { key = 'v', mods = 'CTRL', action = act.PasteFrom('Clipboard') },
    { key = 'v', mods = 'CTRL|SHIFT', action = act.PasteFrom('Clipboard') },

    -- Tabs
    { key = 't', mods = 'CTRL|SHIFT', action = act.SpawnTab('CurrentPaneDomain') },
    { key = 'w', mods = 'CTRL|SHIFT', action = act.CloseCurrentTab({ confirm = false }) },
    { key = 'Tab', mods = 'CTRL', action = act.ActivateTabRelative(1) },
    { key = 'Tab', mods = 'CTRL|SHIFT', action = act.ActivateTabRelative(-1) },

    -- Search / launcher
    { key = 'f', mods = 'CTRL|SHIFT', action = act.Search({ CaseSensitiveString = '' }) },
    { key = 'p', mods = 'CTRL|SHIFT', action = act.ActivateCommandPalette },

    -- Alt-number tab switching
    { key = '1', mods = 'ALT', action = act.ActivateTab(0) },
    { key = '2', mods = 'ALT', action = act.ActivateTab(1) },
    { key = '3', mods = 'ALT', action = act.ActivateTab(2) },
    { key = '4', mods = 'ALT', action = act.ActivateTab(3) },
  },

  -- Keep hyperlinks useful in terminal output.
  hyperlink_rules = wezterm.default_hyperlink_rules(),
}
