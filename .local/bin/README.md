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
- `sysup` upgrades this host by detecting its OS family and running the
  matching backend, forwarding every argument. Run the backend directly for its
  own help text and family-specific flags.
- `archup` upgrades Arch hosts, rebuilds broken AUR packages when `yay` is
  available, restarts active systemd services shipped by upgraded or rebuilt
  packages, and runs post-upgrade checks for missing shared libraries and
  failed systemd units. Package installation is noninteractive by default for
  the yay upgrade, automatic AUR rebuild, and pacman fallback; pass `--confirm`
  after `--` to restore package-manager prompts.
- `debup` upgrades Debian and Ubuntu hosts within their installed release. It
  runs `apt-get --with-new-pkgs upgrade` so new dependencies install but no
  package is removed; `--full-upgrade` permits removals, and neither crosses a
  release. Package installation is noninteractive by default, and locally
  modified config files are always kept. `apt-get update` is retried on lock
  contention, because `DPkg::Lock::Timeout` covers only the dpkg locks and
  `unattended-upgrades` holds the lists lock routinely. Services
  are restarted through `needrestart` when it is installed, otherwise by
  mapping upgraded packages to their active units. Post-upgrade checks cover
  dpkg and apt integrity, held packages, a pending reboot, and config files
  awaiting a manual merge; the reboot check prefers `needrestart`'s kernel
  status, since stock Debian never writes `/var/run/reboot-required`.
  `--autoremove` purges packages no longer required, which is otherwise only
  reported. `--check-only` never restarts a service.

  The three share their CLI conventions, run sequence, systemd handling, and OS
  detection through `~/.local/lib/dot/sysup`; each backend supplies only its
  package-manager specifics.

## Hook And Tool Front Doors

- `validate-commit-msg` checks commit message policy.

Reusable tool commands such as `ettun`, `sley`, `agent-hook-*`,
`claude-session-name`, `autoformat`, `autolint`, `checkrun`,
`git-absorb-and-rebase`, `tmux-save-session`, `tmux-restore-session`,
`tmux-clip-paste`, `wezterm-switch-tab`, and `wezterm-move-tab` are installed
by `shdeps` from their owning dependency repos. The WezTerm tab switch/move
helpers are owned by `termnav`; tmux session save/restore and clip paste are
owned by `tmux-tools`. The resilient ET tunnel command is owned by `ettun`;
dotfiles only declares that dependency.

## Terminal Helpers

- `clip` manages clipboard history and provides the picker used by tmux.
- `shell-time` profiles shell startup cost for zsh or bash.

When adding a new script, keep reusable logic out of `.local/bin` once it has a
second consumer.

Work-specific scripts are documented separately in
`~/.local/share/doc/dot/work-scripts.md` when the work overlay is present.
