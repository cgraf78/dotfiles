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
  failed systemd units.
- `debup` upgrades Debian and Ubuntu hosts within their installed release. It
  runs `apt-get --with-new-pkgs upgrade` so new dependencies install but no
  package is removed; `--full-upgrade` permits removals, and neither crosses a
  release. Locally modified config files are always kept. Services are
  restarted through `needrestart` when it is installed, otherwise by mapping
  upgraded packages to their active units. Post-upgrade checks cover dpkg and
  apt integrity, held packages, a pending reboot, and config files awaiting a
  manual merge. `--autoremove` purges packages no longer required, which is
  otherwise only reported.

  The three share their run sequence, systemd handling, and OS detection
  through `~/.local/lib/dot/sysup`; each backend supplies only its package
  manager specifics.
- `et-tunnel VIA LOCAL_PORT TARGET TARGET_PORT` exposes a remote TCP endpoint
  on local loopback through an Eternal Terminal server. It stays in the
  foreground and lets ET recover from roaming and network loss. A token-owned,
  loopback-only `socat` or `ncat` supervisor cleans up on `Ctrl-C`; the next
  same-client launch also reclaims an interrupted cleanup. Remote bind
  conflicts retry five distinct port sets. The ET client is managed on macOS.
  Both ends need `base64`, `gzip`, and a SHA-256 tool (`sha256sum`, `shasum`, or
  `openssl`); VIA also needs `/bin/sh`, `etserver`, `flock`, and `socat`
  (preferred) or `ncat`. The `flock` lock serializes
  same-client startup and is released by the kernel even after abrupt
  termination. The `ncat` fallback is suitable for long-lived
  full-duplex protocols such as RDP and VNC, but protocols that half-close
  their request before reading a response need `socat` for transparent EOF
  handling. Set `ET_TUNNEL_TRANSPORT` to an executable adapter for connection
  environments that wrap ET. The adapter receives `VIA`, the complete
  comma-separated ET tunnel specification, and a bounded remote bootstrap
  command as three positional arguments. After ET connects, the launcher
  reads a constant role banner to distinguish the bootstrap listener from the
  supervisor, then uploads the digest-bound payload through the same private
  control forward with an input limit and overall deadline. This keeps the
  transport contract to two forwarded channels for compatibility with older ET
  servers. The adapter must remain in the foreground for the lifetime of the ET
  connection.

## Hook And Tool Front Doors

- `validate-commit-msg` checks commit message policy.

Reusable tool commands such as `sley`, `agent-hook-*`,
`claude-session-name`, `autoformat`, `autolint`, `checkrun`,
`git-absorb-and-rebase`, `tmux-save-session`, `tmux-restore-session`,
`tmux-clip-paste`, `wezterm-switch-tab`, and `wezterm-move-tab` are installed
by `shdeps` from their owning dependency repos. The WezTerm tab switch/move
helpers are owned by `termnav`; tmux session save/restore and clip paste are
owned by `tmux-tools`.

## Terminal Helpers

- `clip` manages clipboard history and provides the picker used by tmux.
- `shell-time` profiles shell startup cost for zsh or bash.

When adding a new script, keep reusable logic out of `.local/bin` once it has a
second consumer.

Work-specific scripts are documented separately in
`~/.local/share/doc/dot/work-scripts.md` when the work overlay is present.
