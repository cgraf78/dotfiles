local wezterm = require 'wezterm'
local act = wezterm.action

return {
  -- Launch directly into WSL by default.
  -- Change the distro name here if needed (see: wsl -l -v).
  default_prog = { 'wsl.exe', '-d', 'archlinux', '--cd', '/home/chris' },

  -- Appearance
  font = wezterm.font_with_fallback({
    'Consolas',
    'Cascadia Mono',
  }),
  font_size = 9.0,
  line_height = 1.0,
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

  -- Behavior
  scrollback_lines = 20000,
  check_for_updates = false,
  automatically_reload_config = true,
  audible_bell = 'Disabled',
  default_cursor_style = 'SteadyBar',

  keys = {
    -- Try to make Shift+Enter distinct from plain Enter for TUIs.
    -- If your app doesn't like this, switch to the Ctrl+J variant below.
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
