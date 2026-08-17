# tmux Merge Hook

The tmux merge hook reloads `~/.config/tmux/tmux.conf` in the running default
tmux server after `dot update`. It does nothing when tmux is not installed or
no default server is running, so unattended updates never start a server.

The hook implementation is
`~/.local/lib/dotfiles/merge-hooks.d/tmux.sh`.
