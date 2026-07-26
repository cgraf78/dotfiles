# Sapling Hooks

This directory contains Sapling hook entry points. It mirrors the Git hook
policy where Sapling uses different hook names or wiring.

`sley-commit-gate` delegates to `sley ready --fix --commit` for
Sapling commands that create or rewrite commits. This intentionally includes
the `verify` phase so `sley verify` extensions run for human and agent Sapling
workflows through the same native hook path.

The hook is installed for Sapling command hooks such as `precommit`,
`pre-amend`, `pre-absorb`, `pre-rebase`, `pre-fold`, and related commit
mutation commands. Abort, dry-run, no-commit, and metadata-only command forms
skip the readiness gate.

Keep Sapling hooks thin and aligned with Git hooks unless Sapling needs a
different integration shape. Shared behavior should stay in `sley`, Checkrun,
or the relevant dependency repo.
