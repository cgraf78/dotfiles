# Dotfiles

<!-- agent-rule-id: global-dotfiles-management -->

The base client uses `~/.dotfiles` as a separate Git directory with `$HOME` as
its worktree, plus overlay repos discovered from
`~/.config/dot/overlays.d/*.conf`. Full documentation:
`~/.local/share/doc/dotfiles/dotfiles.md`.

- Before operating on the base repository, an overlay, the `dot` client, or
  generated dotfiles state, read
  `~/.config/agent-rules/playbooks.d/dotfiles/operations.md`.
