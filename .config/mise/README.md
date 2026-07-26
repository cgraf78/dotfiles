# mise Config

This directory pins tool versions used by the dotfiles toolchain.

## Files

- `config.toml` declares global tool versions and plugins.
- `mise.lock` pins resolved versions for reproducible installs.

`dot update` runs `mise install` through the merge hook in
`~/.local/lib/dot/core/merge-hooks/mise.sh`. CI does the same after bootstrap, then
checks that required lint and formatting tools are available.

## Policy

Use mise for developer tools that need a pinned upstream version across
platforms. Use shdeps for system packages, GitHub release downloads, custom
install hooks, and tools that are better managed outside mise.
