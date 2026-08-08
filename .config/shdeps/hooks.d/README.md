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
manages the real Neovim binary at a private path. On Android/Termux, the hook
uses Termux's native `neovim` package and links its binary behind that launcher.

## Cross-repository PR staging

`cgraf78/agentguard.sh` is a deliberately temporary bridge for the paired
AgentGuard and dotfiles pull requests. A dotfiles pull-request bootstrap cannot
normally see an unmerged commit in another repository, so the hook stages the
immutable provider commit only inside `cgraf78/dotfiles` GitHub PR jobs. It
never changes fleet installs or developer clones, and all per-agent merge code
continues to resolve provider assets through the ordinary Shdeps API.

Remove the hook after AgentGuard PR #75 lands. At that point the default branch
contains the integration assets and retaining a commit pin would only add
maintenance cost without improving safety.
