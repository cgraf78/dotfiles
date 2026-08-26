local wezterm = require("wezterm")
local act = wezterm.action

local target = wezterm.target_triple or ""
local is_macos = target:find("darwin", 1, true) ~= nil
local is_windows = target:find("windows", 1, true) ~= nil
local is_linux = target:find("linux", 1, true) ~= nil

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

local function pass_key(key, mods)
  local send = { key = key }
  if mods ~= "NONE" then
    send.mods = mods
  end
  return bind(key, mods, act.SendKey(send))
end

local function release_key(key, mods)
  return bind(key, mods, act.DisableDefaultAssignment)
end

local function append_all(dst, src)
  for _, item in ipairs(src) do
    table.insert(dst, item)
  end
end

local function dx12_adapter()
  if type(wezterm.gui) ~= "table" or type(wezterm.gui.enumerate_gpus) ~= "function" then
    return nil
  end

  local ok, adapters = pcall(wezterm.gui.enumerate_gpus)
  if not ok or type(adapters) ~= "table" then
    return nil
  end

  for _, adapter in ipairs(adapters) do
    if adapter.backend == "Dx12" and adapter.device_type == "DiscreteGpu" then
      return adapter
    end
  end

  return nil
end

-- Copied WSL wrappers do not always have debug source paths, so pass the active
-- config dir through a short-lived global that termnav-module.lua can read.
-- selene: allow(global_usage)
local function load_config_module(name)
  local previous_config_dir = rawget(_G, "dotfiles_wezterm_config_dir")
  _G.dotfiles_wezterm_config_dir = wezterm.config_dir

  local ok, module = pcall(dofile, wezterm.config_dir .. "/" .. name)
  if previous_config_dir == nil then
    _G.dotfiles_wezterm_config_dir = nil
  else
    _G.dotfiles_wezterm_config_dir = previous_config_dir
  end

  if not ok then
    error(module, 2)
  end

  return module
end

-- Keep environment-specific link patterns out of the base WezTerm config.
-- Overlay modules can return one rule, a list of rules, or an apply function.
local function log_extension_error(path, message)
  if type(wezterm.log_error) == "function" then
    wezterm.log_error("wezterm extension " .. path .. ": " .. tostring(message))
  end
end

local function sorted_glob(pattern)
  local files = {}
  if type(wezterm.glob) ~= "function" then
    return files
  end

  local ok, matches = pcall(wezterm.glob, pattern)
  if not ok or type(matches) ~= "table" then
    return files
  end

  append_all(files, matches)
  table.sort(files)
  return files
end

local function read_trimmed_file(path)
  local handle = io.open(path, "r")
  if handle == nil then
    return nil
  end

  local value = handle:read("*l")
  handle:close()
  if value == nil then
    return nil
  end

  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function append_rule_extension(rules, extension)
  if type(extension) ~= "table" then
    return
  end

  if extension.regex and extension.format then
    table.insert(rules, extension)
  else
    append_all(rules, extension)
  end
end

local function apply_hyperlink_rule_extensions(rules)
  for _, path in ipairs(sorted_glob(wezterm.config_dir .. "/hyperlink-rules.d/*.lua")) do
    local ok, extension = pcall(dofile, path)
    if not ok then
      log_extension_error(path, extension)
    elseif type(extension) == "function" then
      local applied, result = pcall(extension, wezterm, rules)
      if not applied then
        log_extension_error(path, result)
      else
        append_rule_extension(rules, result)
      end
    elseif type(extension) == "table" and type(extension.apply) == "function" then
      local applied, result = pcall(extension.apply, wezterm, rules)
      if not applied then
        log_extension_error(path, result)
      else
        append_rule_extension(rules, result)
      end
    else
      append_rule_extension(rules, extension)
    end
  end
end

local termnav_routes = load_config_module("link-routes.lua").new(wezterm)

-- Dotfiles owns key policy; termnav owns the pane metadata protocol that tells
-- us whether the active pane is currently controlled by nvim.
local function is_nvim(pane)
  return termnav_routes.is_nvim(pane)
end

local function is_tmux(pane)
  return termnav_routes.is_tmux(pane)
end

local function nvim_tmux_or_wezterm(nvim_key, nvim_mods, tmux_key, tmux_mods, wezterm_action)
  return wezterm.action_callback(function(window, pane)
    if is_nvim(pane) then
      window:perform_action(act.SendKey({ key = nvim_key, mods = nvim_mods }), pane)
    elseif is_tmux(pane) then
      window:perform_action(act.SendKey({ key = tmux_key, mods = tmux_mods }), pane)
    else
      window:perform_action(wezterm_action, pane)
    end
  end)
end

local function terminal_or_wezterm(terminal_action, wezterm_action)
  return wezterm.action_callback(function(window, pane)
    if is_nvim(pane) or is_tmux(pane) then
      window:perform_action(terminal_action, pane)
    else
      window:perform_action(wezterm_action, pane)
    end
  end)
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
local tab_font_size
local line_height
local default_prog
local window_decorations = "TITLE|RESIZE"
local macos_window_background_blur = 0
local front_end
local webgpu_power_preference
local webgpu_preferred_adapter
local freetype_load_target
local freetype_render_target
local bell_command
local audible_bell = "SystemBeep"
local termnav_ssh_control_hosts = os.getenv("TERMNAV_SSH_CONTROL_HOSTS")
  or read_trimmed_file(wezterm.config_dir .. "/termnav-ssh-control-hosts")
  or ""

if is_macos then
  table.insert(font_names, "Menlo")
  font_size = 11
  tab_font_size = 11.0
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
  bell_command = { "afplay", "/System/Library/Sounds/Glass.aiff" }
elseif is_windows then
  table.insert(font_names, "Consolas")
  font_size = 9.0
  tab_font_size = 9.0
  line_height = 1.0
  -- Prefer the native Windows GPU API instead of accepting WebGPU's first
  -- enumerated backend, which can be Vulkan even when discrete DX12 is ready.
  front_end = "WebGpu"
  webgpu_power_preference = "HighPerformance"
  webgpu_preferred_adapter = dx12_adapter()
  -- WSL needs an explicit program; can't use the login shell.
  default_prog = { "wsl.exe", "-d", "archlinux", "--cd", "~", "--exec", "/bin/zsh", "-l" }
  bell_command = {
    "powershell.exe",
    "-NoProfile",
    "-NonInteractive",
    "-Command",
    "[System.Media.SystemSounds]::Asterisk.Play()",
  }
elseif is_linux then
  table.insert(font_names, "DejaVu Sans Mono")
  font_size = 9.5
  tab_font_size = 9.5
  line_height = 1.0
  -- WebGPU uses Vulkan on Linux while retaining automatic adapter selection.
  front_end = "WebGpu"
  bell_command = { "paplay", "/usr/share/sounds/freedesktop/stereo/bell.oga" }
else
  table.insert(font_names, "monospace")
  font_size = 10.0
  tab_font_size = 10.0
  line_height = 1.0
end

if bell_command then
  -- The bell event below owns playback on supported platforms. Disabling the
  -- native renderer avoids duplicate sounds where SystemBeep happens to work.
  audible_bell = "Disabled"
end

local keys = {}

-- Terminal/application pass-through policy.
--
-- Add future terminal/application-owned keys here when WezTerm has a default
-- for the chord, the key is punctuation/function-key based, or terminal
-- encoding has historically been fragile. The owning app may be nvim or tmux
-- today, but the boundary is simply "the terminal application owns this key".
-- Use pass_key() when WezTerm should document app ownership by forwarding the
-- key, release_key() when the built-in default only needs to be disabled,
-- SendString only for a known escape-sequence workaround, and
-- nvim_tmux_or_wezterm() when the same chord should keep a useful WezTerm action
-- outside terminal-owned contexts.
--
-- macOS-specific escape-sequence workarounds live in the macOS block below so
-- platform shortcuts stay separated from cross-platform terminal policy.
append_all(keys, {
  -- Escape-sequence workarounds for modified keys that terminals do not always
  -- encode distinctly without help.
  -- Shift+Enter: send CSI u sequence (kitty keyboard protocol) so TUIs can
  -- distinguish it from plain Enter. Requires tmux extended-keys passthrough
  -- (set via terminal-features extkeys in tmux.conf).
  bind("Enter", "SHIFT", act.SendString("\x1b[13;2u")),

  -- Pass Shift-PageUp/Down to the application (overrides WezTerm scrollback)
  bind("PageUp", "SHIFT", act.SendString("\x1b[5;2~")),
  bind("PageDown", "SHIFT", act.SendString("\x1b[6;2~")),
  bind("PageUp", "CTRL|SHIFT", act.SendString("\x1b[5;6~")),
  bind("PageDown", "CTRL|SHIFT", act.SendString("\x1b[6;6~")),

  -- Pass Ctrl-Shift-Up/Down to the application (overrides WezTerm scrollback)
  bind("UpArrow", "CTRL|SHIFT", act.SendString("\x1b[1;6A")),
  bind("DownArrow", "CTRL|SHIFT", act.SendString("\x1b[1;6B")),

  -- Neovim owns these editor chords in the active terminal pane.
  pass_key(".", "CTRL"), -- nvim: code actions.
  pass_key("/", "CTRL"), -- nvim: toggle comments.
  pass_key("F2", "NONE"), -- nvim: rename symbol.
  pass_key("F12", "NONE"), -- nvim: go to definition.
  pass_key("F12", "SHIFT"), -- nvim: find references.
  pass_key("v", "CTRL|SHIFT"), -- nvim: yank history; tmux rewrites it safely.
  release_key("f", "CTRL|SHIFT"), -- nvim: workspace search instead of WezTerm find.
  pass_key("g", "CTRL"), -- nvim: Go to Line.
  -- Preserve these VS Code chords through WezTerm and tmux even where plain
  -- Ctrl-Shift letters would otherwise collapse into Enter or Ctrl-E. The
  -- existing <leader>xx and <leader>fE mappings remain portable fallbacks.
  bind("m", "CTRL|SHIFT", act.SendString("\x1b[109;6u")),
  bind("e", "CTRL|SHIFT", act.SendString("\x1b[101;6u")),
  release_key("p", "CTRL|SHIFT"), -- nvim: command palette instead of WezTerm launcher.

  -- Conditional ownership: buffers belong to nvim while it is focused, and to
  -- tmux windows while tmux owns the pane. WezTerm tabs own the chord elsewhere.
  bind(
    "Tab",
    "CTRL",
    nvim_tmux_or_wezterm("Tab", "CTRL", "Tab", "CTRL", act.ActivateTabRelative(1))
  ),
  bind(
    "Tab",
    "CTRL|SHIFT",
    nvim_tmux_or_wezterm("Tab", "CTRL|SHIFT", "Tab", "CTRL|SHIFT", act.ActivateTabRelative(-1))
  ),
  bind("{", "ALT|SHIFT", terminal_or_wezterm(act.SendString("\x1b{"), act.MoveTabRelative(-1))),
  bind("}", "ALT|SHIFT", terminal_or_wezterm(act.SendString("\x1b}"), act.MoveTabRelative(1))),
})

-- WezTerm-owned controls. Add bindings here only when WezTerm, not the active
-- terminal application, is supposed to handle the chord.
append_all(keys, {
  -- Font size controls
  bind("=", "CTRL", act.IncreaseFontSize),
  bind("-", "CTRL", act.DecreaseFontSize),
  bind("0", "CTRL", act.ResetFontSize),

  -- Clipboard
  bind("c", "CTRL", wezterm.action_callback(copy_or_interrupt)),
  bind("c", "CTRL|SHIFT", act.CopyTo("Clipboard")),
  bind("v", "CTRL", act.PasteFrom("Clipboard")),

  -- Tabs / windows
  bind("t", "CTRL", act.SpawnTab("DefaultDomain")),
  bind("t", "CTRL|SHIFT", act.SpawnTab("DefaultDomain")),
  bind("w", "CTRL|SHIFT", act.CloseCurrentTab({ confirm = false })),
  bind("{", "CTRL", act.ActivateTabRelative(-1)),
  bind("}", "CTRL", act.ActivateTabRelative(1)),

  -- Tab utilities
  bind("r", "CTRL|SHIFT", wezterm.action_callback(prompt_rename_tab)),

  -- Alt-number tab switching
  bind("1", "ALT", act.ActivateTab(0)),
  bind("2", "ALT", act.ActivateTab(1)),
  bind("3", "ALT", act.ActivateTab(2)),
  bind("4", "ALT", act.ActivateTab(3)),
})

if is_macos then
  -- Native-feeling macOS aliases mirroring the cross-platform Ctrl bindings.
  append_all(keys, {
    -- Font size controls
    bind("=", "SUPER", act.IncreaseFontSize),
    bind("-", "SUPER", act.DecreaseFontSize),
    bind("0", "SUPER", act.ResetFontSize),

    -- Clipboard
    bind("c", "SUPER", act.CopyTo("Clipboard")),
    bind("v", "SUPER", act.PasteFrom("Clipboard")),

    -- Tabs / windows
    bind("t", "SUPER", act.SpawnTab("DefaultDomain")),
    bind("T", "SUPER", act.SpawnTab("DefaultDomain")),
    bind("w", "SUPER", act.CloseCurrentTab({ confirm = false })),
    bind("W", "SUPER", act.CloseCurrentTab({ confirm = false })),
    bind("n", "SUPER", act.SpawnWindow),
    bind("r", "SUPER|SHIFT", wezterm.action_callback(prompt_rename_tab)),
    bind("Tab", "SUPER", act.ActivateTabRelative(1)),
    bind("Tab", "SUPER|SHIFT", act.ActivateTabRelative(-1)),
    bind("[", "SUPER|SHIFT", act.ActivateTabRelative(-1)),
    bind("]", "SUPER|SHIFT", act.ActivateTabRelative(1)),

    -- Search / launcher
    bind("f", "SUPER", act.Search({ CaseSensitiveString = "" })),
    bind("g", "SUPER", act.CopyMode("NextMatch")),
    bind("g", "SUPER|SHIFT", act.CopyMode("PriorMatch")),
    bind("p", "SUPER|SHIFT", act.ActivateCommandPalette),

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
-- Kept in a module so URI routing can be tested with fake panes. WezTerm itself
-- only exposes this behavior through GUI click events, which are hard to cover
-- in the dotfiles test suite.
termnav_routes.setup()

-- =============================================================================
-- Terminal bell
-- =============================================================================
-- BEL is the portable transport across local shells, SSH, and tmux. Render it
-- in the GUI client because WezTerm's SystemBeep is silent on Wayland and can
-- be unavailable on other desktop setups.
wezterm.on("bell", function()
  if bell_command then
    wezterm.background_child_process(bell_command)
  end
end)

-- =============================================================================
-- Terminal user-variable routing
-- =============================================================================
wezterm.on("user-var-changed", function(window, pane, name, value)
  if name == "term_open_url" and value ~= "" then
    wezterm.open_with(value)
  elseif name == "DOT_SWITCH_TAB" and value ~= "" then
    local direction = value:match("^([^:]+):") or value
    if direction == "next" or direction == "previous" then
      local relative = direction == "previous" and -1 or 1
      window:perform_action(act.ActivateTabRelative(relative), pane)
    end
  elseif name == "DOT_MOVE_TAB" and value ~= "" then
    local direction = value:match("^([^:]+):") or value
    if direction == "left" or direction == "right" then
      local relative = direction == "left" and -1 or 1
      window:perform_action(act.MoveTabRelative(relative), pane)
    end
  end
end)

-- =============================================================================
-- Config
-- =============================================================================
return {
  default_prog = default_prog,
  set_environment_variables = {
    TERMNAV_SSH_CONTROL_HOSTS = termnav_ssh_control_hosts,
  },

  color_scheme = "Night Owl (Gogh)",

  colors = {
    tab_bar = {
      inactive_tab = {
        bg_color = "#011627",
        fg_color = "#5f7e97",
      },
      active_tab = {
        bg_color = "#1d3b53",
        fg_color = "#d6deeb",
      },
      new_tab = {
        bg_color = "#011627",
        fg_color = "#5f7e97",
      },
    },
  },

  -- Appearance
  font = font_with_fallback(font_names),
  font_size = font_size,
  line_height = line_height,
  front_end = front_end,
  webgpu_power_preference = webgpu_power_preference,
  webgpu_preferred_adapter = webgpu_preferred_adapter,
  freetype_load_target = freetype_load_target,
  freetype_render_target = freetype_render_target,
  enable_scroll_bar = false,
  hide_tab_bar_if_only_one_tab = true,
  initial_cols = 140,
  initial_rows = 36,
  use_fancy_tab_bar = true,
  tab_bar_at_bottom = false,
  window_frame = {
    font_size = tab_font_size,
    active_titlebar_bg = "#011627",
    inactive_titlebar_bg = "#011627",
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
  bypass_mouse_reporting_modifiers = "SHIFT",
  scrollback_lines = 20000,
  check_for_updates = false,
  automatically_reload_config = true,
  swallow_mouse_click_on_window_focus = true,
  audible_bell = audible_bell,
  default_cursor_style = "BlinkingBlock",

  keys = keys,

  mouse_bindings = {
    -- Ctrl-click opens hyperlinks when WezTerm owns the mouse. Panes with
    -- mouse reporting active, such as tmux/nvim, must receive the real mouse
    -- event so nvim can use click coordinates for LSP-aware navigation; tmux
    -- has matching Ctrl-click bindings for terminal panes it owns.
    {
      event = { Down = { streak = 1, button = "Left" } },
      mods = "CTRL",
      action = act.Nop,
    },
    {
      event = { Up = { streak = 1, button = "Left" } },
      mods = "CTRL",
      action = act.CompleteSelectionOrOpenLinkAtMouseCursor("ClipboardAndPrimarySelection"),
    },
    {
      event = { Drag = { streak = 1, button = "Left" } },
      mods = "CTRL",
      action = act.Nop,
    },
  },

  -- Keep hyperlinks useful in terminal output.
  hyperlink_rules = (function()
    local rules = wezterm.default_hyperlink_rules()

    -- Public URL fallbacks that WezTerm's default rules do not always claim.
    -- Keep this ordered before file-path rules: many browser targets contain
    -- slashes or colons and would otherwise look like nvim-open candidates.
    load_config_module("public-link-rules.lua").add_public_link_rules(rules)

    -- Relative file paths (must contain /) with optional :line:col.
    -- Inserted FIRST so that "src/foo/bar.cpp" is matched in full
    -- before the absolute rule can grab "/foo/bar.cpp" out of it.
    -- Tmux pane border glyphs are excluded so regex highlighting has a hard
    -- stop at common split boundaries even though WezTerm does not know tmux
    -- pane geometry. Ctrl-click gets a stronger pane-aware path through tmux.
    -- The quoted variants intentionally avoid ':' before the first slash. That
    -- keeps "https://..." and friends owned by WezTerm's default URL rules while
    -- still linking quoted paths that start path-like and contain spaces.
    table.insert(rules, {
      -- Examples: "./project dir/src/file.cpp:12", "/tmp/file with spaces.cpp"
      regex = [["((?:~?/|\.{1,2}/|/|[\w@.+~-]+/)[^"│┃║]+|[\w@.+~-]*\.[-A-Za-z0-9_+]*[A-Za-z_+][-A-Za-z0-9_+]*)((?::\d+){0,2})"]],
      format = "nvim-open://$1$2",
    })

    table.insert(rules, {
      -- Examples: './project dir/src/file.cpp:12', '/tmp/file with spaces.cpp'
      regex = [[\x27((?:~?/|\.{1,2}/|/|[\w@.+~-]+/)[^\x27│┃║]+|[\w@.+~-]*\.[-A-Za-z0-9_+]*[A-Za-z_+][-A-Za-z0-9_+]*)((?::\d+){0,2})\x27]],
      format = "nvim-open://$1$2",
    })

    -- Bare filenames are noisy, so only link them when output includes a
    -- line number, as in compiler/test/grep diagnostics: "file.cpp:42".
    table.insert(rules, {
      -- Examples: file.cpp:42, test_output.log:7:2
      regex = [[(?:^|(?<=[^\w@.+~/'"`-]))([\w@.+~-]+\.[-A-Za-z0-9_+]+(?::\d+){1,2})(?=\s|$|[^\w@+~-])]],
      format = "nvim-open://$1",
    })

    table.insert(rules, {
      -- Examples: src/foo.cpp, pkg/module/file.rs:10:4
      regex = [[(?:^|(?<=[^\w@.+~/'"`-]))([\w@.+~-]+/[^\s:│┃║]*\w(?::\d+){0,2})(?=\s|$|[^\w@+~-])]],
      format = "nvim-open://$1",
    })

    -- Absolute file paths with optional :line:col. The `(?!/)` guard prevents
    -- grabbing the `//host/path` authority from normal URLs; those should remain
    -- browser links, not nvim-open links.
    table.insert(rules, {
      -- Examples: /tmp/foo.cpp, /home/me/project/src/main.rs:42
      regex = [[(?:^|(?<=[^\w.@+~/'"`-]))(/(?!/)[^\s:│┃║]*\w(?::\d+){0,2})(?=\s|$|[^\w@+~-])]],
      format = "nvim-open://$1",
    })

    apply_hyperlink_rule_extensions(rules)

    return rules
  end)(),
}
