# DS Base Configuration

This directory contains the small, always-active `ds` policy used for terminal
sessions and remote connection helpers. The `ds` binary is installed through
Shdeps.

Base owns common connection defaults and reusable session plumbing. Named
development-session profiles belong to `dotfiles-dev`; personal or site-local
values belong to their existing private overlay or an untracked local file.

Keep fragments small and declarative. Shared shell behavior belongs under
`~/.config/shell`, while reusable command behavior belongs in the `ds`
repository.
