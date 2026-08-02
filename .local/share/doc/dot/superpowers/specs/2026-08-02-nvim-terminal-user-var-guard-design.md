# Neovim Terminal User-Variable Guard

## Goal

Prevent an embedded Neovim terminal from rendering Termnav's WezTerm
`SetUserVar` control sequence as visible text while preserving the existing
publication for normal tmux shells.

## Design

`53-wezterm.sh` will defer to Termnav's existing
`_termnav_wezterm_active` predicate before it publishes `DOT_TMUX`. That
predicate already classifies `$NVIM` as an ineligible context, while retaining
the normal WezTerm, tmux, and remote-shell cases. The change remains on the
one-time shell-source path; it adds no prompt-time work.

`wezterm-test` will extend its existing source-time publisher probe with an
`NVIM` context. It will assert that neither Bash nor Zsh publish `DOT_TMUX`
inside Neovim and retain the existing assertions for a tmux shell outside it.

## Error Handling and Compatibility

If an older Termnav installation does not provide the predicate, the dotfiles
publisher will retain its current behavior. This keeps the shell integration
compatible with an unavailable or partially installed dependency and avoids
turning shell startup into a hard failure.
