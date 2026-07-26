# Ripgrep Config

This directory contains the global ripgrep config referenced by
`RIPGREP_CONFIG_PATH` in the shell environment layer.

The non-obvious setting is hyperlink output:

```text
--hostname-bin=nvim-link-host
--hyperlink-format=file://{host}{path}:{line}:{column}
```

`nvim-link-host` comes from the `termnav` dependency repo. It decides whether a
search result should be local or host-qualified so WezTerm/tmux/Neovim
click-through behavior can open the right file on local and remote hosts.

Keep route parsing and opener behavior in `termnav`; this file should only
shape ripgrep output.
