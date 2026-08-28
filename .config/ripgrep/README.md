# Ripgrep Config

This directory contains the global ripgrep config referenced by
`RIPGREP_CONFIG_PATH` in the shell environment layer.

The non-obvious setting is hyperlink output:

```text
--hostname-bin=ripgrep-link-host
--hyperlink-format=file://{host}{path}:{line}:{column}
```

Ripgrep invokes `--hostname-bin` with no arguments. Dotfiles therefore owns the
small `ripgrep-link-host` adapter beside this configuration; it delegates to
the explicit `termnav link-host` interface, which decides whether a
search result should be local or host-qualified so WezTerm/tmux/Neovim
click-through behavior opens the right file on local and remote hosts.

Keep route parsing and opener behavior in `termnav`; this file should only
shape ripgrep output.
