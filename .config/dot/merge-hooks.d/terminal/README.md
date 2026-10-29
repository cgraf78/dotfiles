# macOS Terminal profile

The `terminal` merge hook runs during `dot update` on macOS after Shdeps installs
the Nerd Font. It creates the managed **Dotfiles** profile and explicitly sets
both `Default Window Settings` and `Startup Window Settings` to that profile.
Existing profiles and unrelated application preferences remain unchanged.
On a fresh account, Apple's bundled profiles are retained alongside Dotfiles.

`~/.config/wezterm/appearance.json` supplies both applications' primary font,
macOS font size, initial dimensions, and Night Owl (Gogh) colors. The palette
matches [WezTerm's built-in scheme](https://github.com/wezterm/wezterm/blob/main/config/src/scheme_data.rs).
The font's family and weight select the WezTerm face; its PostScript name selects
the same face in Terminal. Keep these fields aligned when changing fonts.
`profile.json` here owns Terminal-specific settings such as font antialiasing
and the blinking block cursor. Local changes to the managed profile are
replaced on the next update; customize another profile for unmanaged settings.

Preferences are read and written through `defaults`, including readback
verification. Repeated updates do not rewrite matching settings. The profile
is installed before either default selector is changed, and a detected edit
between the initial read and publication aborts the merge. Terminal can still
edit preferences concurrently after that check; avoid editing profiles during
an update.

A running Terminal may retain its old font and theme until a new window is
opened or Terminal is quit and reopened; the hook never closes sessions.
Terminal's native title bar, rendering, padding, and effects differ from
WezTerm, so the profile matches the supported appearance settings.

The implementation is `~/.local/lib/dotfiles/merge-hooks.d/terminal.sh`.
