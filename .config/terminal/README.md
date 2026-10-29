# Shared terminal settings

`settings.json` is the source of truth for settings shared by WezTerm, macOS
Terminal, and iTerm2. WezTerm is the reference behavior. Edit this file instead
of copying values into native application profiles.

The shared fields define the primary font and its macOS point size, Night Owl
palette, initial dimensions, horizontal/vertical spacing, cursor, scrollback,
and terminal type. `send_keys` defines portable modified-key escape sequences
consumed by WezTerm and iTerm2. Native ownership callbacks and application
shortcuts remain in their respective adapters; Terminal retains its native
keyboard handling.

WezTerm reads and watches the real shared file and its dedicated directory
for reloads, including atomic replacements. The relative
`~/.config/wezterm/terminal-settings.json` symlink is a convenient editing entry.
The WSL hook copies the shared data to the Windows home
`.config/terminal/settings.json` before publishing the Windows config.
Terminal and iTerm2 convert the
same source data into their native profile formats during `dot update`, and
select their managed **Dotfiles** profiles as the defaults.

Font family/weight select the WezTerm face; `postscript_name` selects that face
in the macOS applications. Keep these font identifiers aligned when choosing a
different installed font. Native rendering, title bars, and effects differ
between applications.

The original palette comes from WezTerm's built-in Night Owl (Gogh) scheme.
Shared changes are covered by the terminal profile, iTerm2, and WezTerm suites.

| Shared setting | WezTerm | Terminal | iTerm2 |
| --- | --- | --- | --- |
| Font, macOS size, palette, dimensions, spacing, cursor | Shared source | Shared source | Shared source |
| Scrollback and terminal type | Shared source | Shared source | Shared source |
| Ligatures | HarfBuzz features | Native rendering | Native profile flags |
| `send_keys` | Literal send actions | Native key handling | Native send-hex actions |
| Context-sensitive app ownership | Lua callbacks | App-specific behavior | App-specific behavior |

## Editing and applying changes

Start from [the WezTerm editing map](../wezterm/README.md), since WezTerm is the
primary terminal. For a shared change, edit `settings.json` once; do not copy
values into generated profiles or add a second literal in an adapter.

| Source | Responsibility |
| --- | --- |
| `settings.json` | Shared values and portable `send_keys` encodings |
| `../wezterm/wezterm.lua` | WezTerm-native UI, fallback fonts, callbacks, and actions |
| `../dot/merge-hooks.d/terminal/profile.json` | Terminal-only profile policy and managed name |
| `../dot/merge-hooks.d/iterm2/profiles.d/*.json` | iTerm2-only policy, native shortcut actions, managed name/identity |
| `../dot/merge-hooks.d/iterm2/defaults.d/*.tsv` | iTerm2 global preferences such as tab style and pointer gestures |

For a font change, keep `font.family`, `font.weight`, and
`font.postscript_name` pointed at the same installed face. The first two are
WezTerm identifiers; the PostScript name is used by the native macOS adapters.
Change `macos_font_size` for terminal text size. The Nerd Font installation
owner is `~/.config/shdeps/hooks.d/nerd-fonts.sh`; choosing another family also
requires arranging installation on new machines. Native window-title fonts
are application UI policy, separate from terminal text.

For a portable key sequence, edit one `send_keys` entry: `key`, WezTerm-style
`mods`, literal `text` bytes (JSON escapes are supported), and `platform`
(`all` or `macos`). The iTerm2 adapter translates modifiers into AppKit masks
and text into a native send-hex action. WezTerm's conditional nvim/tmux
ownership callbacks stay in Lua; they are not statically reproduced in the
other applications. Terminal retains its native key handling.

Use this workflow:

1. Edit the appropriate source in an isolated checkout following the dotfiles
   operating guide. Ordinary value changes belong in the shared JSON.
2. Run `dot test wezterm terminal-font iterm2 core-merges client-extensions`
   from that checkout. Run the normal full repository checks before landing.
3. After the changes land, run `dot update` from the real home checkout. It
   installs fonts before generating the native profiles.
4. Check the managed Dotfiles profile and the saved default selector. WezTerm
   reloads watched config; iTerm2 reloads DynamicProfiles; Terminal may need a
   new window or relaunch. Relaunch iTerm2 if it retains a previous default.
   The hooks do not close existing sessions.

Do not edit `~/Library/Application Support/iTerm2/DynamicProfiles/` or the
macOS preference plists to make durable changes: those are generated targets.
iTerm2's existing managed GUID is deliberately retained even though it still
contains the historical Windows name. Change its display name in the source
without changing its GUID or managed output filename.

## Adding a shared setting

Start with the existing WezTerm behavior. Add the value to `settings.json`,
then consume it in every adapter that supports it. Native enums and file
formats belong in adapters, not the shared JSON. For example, a block cursor
is 0 in Terminal and 2 in iTerm2; `terminal_settings.py` owns that translation.
Document unsupported behavior as app-specific instead of silently claiming
parity.

Add a regression that changes the shared value away from its default and
checks the resulting native fields or WezTerm configuration. This catches an
adapter that accidentally leaves a hard-coded old value in place. A new test
suite must also be listed in `.github/dot-test-suites.txt` and the ShellCheck
inventory when applicable. Structured-file schema coverage is owned by the
Checkrun policy in the dev overlay; these dotfiles-owned settings have no
external schema and are validated by the adapter tests.

Adapter implementations live under
`~/.local/lib/dotfiles/merge-hooks.d/`: `terminal.sh` / `lib/terminal-font.py`,
`iterm2.sh` / `lib/iterm2-profile.py`, and the WSL copy in `wezterm.sh`.
`lib/terminal_settings.py` contains shared native data conversions.
