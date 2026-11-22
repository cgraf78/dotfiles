# tmux Merge Hook

The tmux merge hook targets the default socket after `dot update`, including
when the command runs from a named tmux server. After a successful reload, the
stamp records the server instance and checksums of `tmux.conf` and every
`conf.d` include. Unchanged inputs on that same server skip the reload. A
replacement server reloads once even when the config is unchanged. Unattended
updates never start a tmux server.

The hook implementation is
`~/.local/lib/dotfiles/merge-hooks.d/tmux.sh`.
