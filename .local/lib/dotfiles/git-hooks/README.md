# Git Hooks

This directory is the global Git hook directory selected by
`~/.config/git/config` through `core.hooksPath`.

It lives under `~/.local/lib/dotfiles` because these files are executable,
dotfiles-owned client policy. It is separate from the standalone Dot public
library and frozen rescue core because Git invokes these entry points directly;
neither runtime loads or dispatches them.

## Hooks

- `pre-commit`, `pre-merge-commit`, `pre-applypatch`, `prepare-commit-msg`, and
  `commit-msg` are activation shims for Sley's generic Git hooks.
- `sley-provider-hook` resolves the Shdeps-managed Sley checkout, verifies the
  requested provider hook and matching CLI are executable, and dispatches
  without evaluating a command string.
- `sley-commit-gate` adds the one dotfiles-specific policy described below,
  then delegates the portable readiness behavior to Sley.
- `commit-msg` selects dotfiles' advanced message-policy provider before
  dispatching to Sley's generic finalized-message hook.

Sley owns the reusable decisions about ordinary commits, merges, patches, and
Git sequencer operations. Keeping those implementations in Sley gives direct
Sley users the same behavior and prevents this activation directory from
becoming a fork.

Dotfiles retains one intentionally local rule: `sley-commit-gate` sets
`SLEY_SKIP_UNTRACKED=1` for the base bare dotfiles repo. That unusual repo uses
all of `$HOME` as its work tree, so an untracked-file walk would be both
expensive and unrelated to the staged commit scope. Sley does not need to know
that personal repository layout.

Normal activation resolves Sley at
`~/.local/share/cgraf78/sley/`, using both its `share/sley/hooks/git/` hooks and
its `bin/sley` CLI. `DOT_SLEY_ROOT` may point at a complete Sley checkout for
cross-repository development and integration tests; selecting both artifacts
from one root prevents hook/CLI version skew. The override is not required on
fleet machines because `dot update` keeps the stable Shdeps checkout current.

## Policy

Keep hooks thin. Portable readiness and commit-message provider dispatch belong
in Sley, formatting and linting policy belongs in Checkrun, and the local
commit-message grammar belongs in `../sley-hooks/validate-commit-msg`.

Hooks that only add advisory checks may degrade gracefully when a dependency is
not installed yet. Hooks that enforce commit readiness should fail closed and
explain which dependency or native bypass is needed.
