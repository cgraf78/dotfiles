# WezTerm Merge Hook

This directory declares the `wezterm` merge-hook instance. It has no
declarative source fragments under `merge-hooks.d`: the hook copies the tracked
`~/.config/wezterm` configuration into the Windows home when running under WSL.

The executable hook implementation lives at
`~/.local/lib/dot/core/merge-hooks/wezterm.sh`.
