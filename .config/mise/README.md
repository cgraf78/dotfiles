# mise Config

This directory pins tool versions used by the dotfiles toolchain.

## Files

- `config.toml` declares global tool versions and plugins.
- `mise.lock` pins resolved versions and release assets for reproducible
  installs across supported platforms.

`dot update` runs `mise install --locked` through the merge hook in
`~/.local/lib/dotfiles/merge-hooks.d/mise.sh`. CI revalidates the lock after
bootstrap, exercises representative locked installs, and checks that required
tools are available.

## Policy

Use mise for portable developer binaries that need a pinned upstream version
across platforms. Prefer Aqua registry entries; use the direct GitHub backend
when a project has predictable release assets and the tracked lock covers every
configured platform.

Use shdeps for system packages, repository dependencies, bootstrap ordering,
custom lifecycle hooks, and tools that mise cannot manage cleanly. Neovim
treats both providers as authoritative and uses Mason only when their commands
are absent.
