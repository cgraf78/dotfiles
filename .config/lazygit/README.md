# Lazygit Config

This directory owns local Lazygit UI and diff-renderer policy.

The important integration is file-link routing: Lazygit uses Delta with
`--hyperlinks-file-link-format="lazygit-edit://{path}:{line}"`. WezTerm and the
terminal navigation stack route those links through `termnav nvim open` so files
open in the active Neovim/tmux workflow instead of starting a separate editor.

Keep generic editor-link parsing in the `termnav` dependency repo. This config
should only choose Lazygit's diff-renderer/link shape.
