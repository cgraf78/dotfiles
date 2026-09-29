# Ripgrep Config

This directory contains the global ripgrep config referenced by
`RIPGREP_CONFIG_PATH` in the shell environment layer. The base `config` holds
search defaults only.

Hyperlink output is editor policy, so it lives in `dotfiles-nvim`. That
overlay's `config.editor` repeats these defaults and adds:

```text
--hostname-bin=ripgrep-link-host
--hyperlink-format=file://{host}{path}:{line}:{column}
```

The overlay's `env.d/60-editor.sh` points `RIPGREP_CONFIG_PATH` at
`config.editor` while it is active. Ripgrep invokes `--hostname-bin` with no
arguments, so `dotfiles-nvim` also owns the small `ripgrep-link-host` adapter;
it delegates to the explicit `termnav link-host` interface, which decides
whether a search result should be local or host-qualified so
WezTerm/tmux/Neovim click-through behavior opens the right file on local and
remote hosts.

Keep route parsing and opener behavior in `termnav`; these files should only
shape ripgrep output.
