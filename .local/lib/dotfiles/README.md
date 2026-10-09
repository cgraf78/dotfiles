# Base Dotfiles Runtime

This tree contains executable client policy that is active for every profile.
The standalone Dot checkout supplies repository convergence, extension
workers, and public APIs; this repository supplies the base hooks and policy
those interfaces execute.

- `pre-sync.d/` prepares selected-overlay transport before synchronization.
- `merge-hooks.d/` contains base application merge hooks and support code.
- `doctor.d/` contains base health checks.
- `tests/` contains base, profile-control, ownership, and composition coverage.
- `shell-loader.sh`, `launcher-real.sh`, `windows.sh`, and
  `shdeps-assets.sh` are shared base helpers.
- `shell-grok-rc.sh` detects and strips the Grok installer block in the thin
  shell loaders; the `grok-rc` merge hook and the dev overlay's grok/agent
  wrappers strip, `dot doctor` only reports.
- `worktree-gc.sh` implements the `dot-worktree-gc` command: discovery, the
  age policy, and empty or orphaned directories, with every per-repository
  branch and checkout decision delegated to `git cleanup-repo` (git-tools).
- `worktree-gc-actions.sh` proves that a checkout's only change is a
  superseded `cgraf78/actions` pin, the one retirement request
  `dot-worktree-gc` makes on its own evidence.
- `worktree-gc-orphans.py` proves and retires checkouts whose Git metadata is
  gone, by exact match against merged history, without recursive deletion.

Editor and development runtime belongs to `dotfiles-nvim` and `dotfiles-dev`.
Executable extensions use only Dot's public hook or doctor API.
