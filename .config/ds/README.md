# DS Base Configuration

This directory is the shared `ds` configuration directory for terminal
sessions and remote connection helpers. The `ds` binary is installed through
Shdeps.

Base tracks only this README; it contributes no `ds` fragments. Selected
overlays add them here: named development-session profiles belong to
`dotfiles-dev`, and personal or site-local connection and profile values
belong to their existing private overlay or an untracked local file.

Keep fragments small and declarative. Shared shell behavior belongs under
`~/.config/shell`, while reusable command behavior belongs in the `ds`
repository.
