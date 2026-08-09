# Local Commands

This README covers dotfiles-owned command entry points tracked in this repo.
At runtime, `~/.local/bin` also contains shdeps-managed links and other local
installs that are not tracked by dotfiles.

Shared implementation should live under `~/.local/lib/dot` or another owning
component; files here should stay thin and command-shaped.

## Dotfiles Commands

- `dot` manages the base bare repo and active overlays.
- `dotbootstrap` installs or repairs a dotfiles checkout.
- `dot-test` runs the dotfiles test suite.
- `git` routes normal repositories to real Git and `$HOME` dotfiles paths to
  the base bare repo.
- `nvim` reuses an existing Neovim pane in the current tmux window for simple
  interactive-shell file opens, then falls back to the real Neovim binary.

## Hook And Tool Front Doors

- `validate-commit-msg` checks commit message policy.

Reusable tool commands such as `ettun`, `sley`, `sysup`, `agent-hook-*`,
`claude-session-name`, `autoformat`, `autolint`, `checkrun`,
`git-absorb-and-rebase`, `tmux-save-session`, `tmux-restore-session`,
`tmux-clip-paste`, `wezterm-switch-tab`, and `wezterm-move-tab` are installed
by `shdeps` from their owning dependency repos. The WezTerm tab switch/move
helpers are owned by `termnav`; tmux session save/restore and clip paste are
owned by `tmux-tools`. The resilient ET tunnel command is owned by `ettun`;
the unified system updater is owned by `sysup`. Only the `sysup` front door is
public; its Arch and Debian family backends are provider-internal details.
Dotfiles only declares those dependencies.

## Terminal Helpers

- `clip` manages clipboard history and provides the picker used by tmux.
- `shell-time` profiles shell startup cost for zsh or bash.

When adding a new script, keep reusable logic out of `.local/bin` once it has a
second consumer.

Work-specific scripts are documented separately in
`~/.local/share/doc/dot/work-scripts.md` when the work overlay is present.
