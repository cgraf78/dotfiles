# shdeps Hooks

This directory contains dotfiles-specific shdeps hooks. The dependency
declarations live in `../00-toolchains.conf` and `../10-deps.conf`; hook files
add behavior that the generic shdeps methods cannot express cleanly.

## Naming

Hook paths match dependency names:

- `name.sh` for simple dependency names such as `rubocop`
- `owner/repo.sh` for slash-delimited GitHub dependency names such as
  `neovim/neovim`

## Hook API

Hooks may define shdeps lifecycle functions such as:

- `exists()` to decide whether the dependency is already satisfied
- `version()` to render installed status
- `install()` for custom installs
- `post()` for follow-up work after a generic install
- `uninstall()` for cleanup during pruning

Keep hooks idempotent. `dot update` runs regularly and may run on constrained
hosts, CI, WSL, or headless Linux.

## Policy

Use hooks for local integration boundaries, not for normal package selection.
Prefer registry aliases and the generic `pkg`, `github`, `cargo`, `go`, or
`uv` methods when they are enough.

Optional formatter and linter hooks should not install a full language runtime
as a hidden dependency. If the runtime is absent, skip cleanly or mark the
dependency as skipped so future updates are quiet until the runtime appears.

When a PATH-visible command is owned by dotfiles, keep the public launcher in
dotfiles and install the dependency binary behind it. The Neovim hook is the
main example: `~/.local/bin/nvim` stays the tmux-aware launcher, while shdeps
manages the real Neovim binary at a private path.
