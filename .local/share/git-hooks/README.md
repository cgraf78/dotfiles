# Git Hooks

This directory is the global Git hook directory selected by
`~/.config/git/config` through `core.hooksPath`.

## Hooks

- `sley-commit-gate` delegates to `sley ready --fix --commit`.
- `pre-commit` gates normal `git commit` and `git commit --amend`.
- `pre-merge-commit` gates automatic merge commits.
- `pre-applypatch` gates commits created by `git am`.
- `prepare-commit-msg` gates sequencer commits that bypass `pre-commit`, such
  as `git cherry-pick`, `git revert`, and conflict-resolved `git rebase
  --continue`.
- `commit-msg` delegates to `validate-commit-msg --format git`.

The commit-readiness hooks run for human and agent commits through the same
path. The shared gate sets `SLEY_SKIP_UNTRACKED=1` for the base bare dotfiles
repo so commit checks stay scoped to staged files instead of walking all of
`$HOME`.

## Policy

Keep hooks thin. Shared readiness behavior belongs in `sley`, formatting and
linting policy belongs in Checkrun, and commit-message policy belongs in
`validate-commit-msg`.

Hooks that only add advisory checks may degrade gracefully when a dependency is
not installed yet. Hooks that enforce commit readiness should fail closed and
explain which dependency or native bypass is needed.
