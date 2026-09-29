# tmux Merge Hook

The tmux merge hook reloads `~/.config/tmux/tmux.conf` in the running default
tmux server after `dot update` when the config changed. A stamp records
checksums of `tmux.conf` and every `conf.d` include after each successful
reload; when none of those inputs changed, the hook skips the reload. It does
nothing when tmux is not installed or no default server is running, so
unattended updates never start a server.

The hook implementation is
`~/.local/lib/dotfiles/merge-hooks.d/tmux.sh`.
