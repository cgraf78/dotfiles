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
- `agent-playbooks.sh` discovers the trusted agent playbooks selected by
  dotfiles policy.
- `shell-grok-rc.sh` strips the Grok installer block from the thin shell
  loaders.
- `worktree-gc.sh` implements the `dot-worktree-gc` command.

Editor and development runtime belongs to `dotfiles-nvim` and `dotfiles-dev`.
Executable extensions use only Dot's public hook or doctor API.
