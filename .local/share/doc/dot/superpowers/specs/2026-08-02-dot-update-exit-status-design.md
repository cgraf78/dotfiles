# `dot update` Exit Status Design

## Problem

`dot update` deliberately continues through independent stages after a
failure, but the launcher currently exits zero unconditionally. A failed
dependency install or config merge therefore looks successful to cron and CI
even though the dashboard reports an error.

## Exit-status contract

`dot update` will remain best effort: after a recoverable stage failure, it
will run every later safe stage and finish the dashboard. It will return
nonzero after convergence if any required operation failed.

Required failures include:

- repository synchronization;
- overlay linking;
- Shdeps bootstrap or dependency update;
- config merge hooks.

An initial Shdeps bootstrap failure is not recoverable: overlay platform and
host filters are supplied by Shdeps, so discovery cannot safely continue
without it. That failure will return nonzero before overlay discovery. A
dependency-update failure after bootstrap is recoverable and will not prevent
config merges or cleanup.

Advisory conditions remain successful:

- dependency warnings that Shdeps itself reports with a zero status;
- optional overlay skips;
- cron's intentional dirty-worktree skip;
- cron lock contention that means another update owns the work;
- best-effort worktree normalization.

The `DOT_FORCE` and `SHDEPS_FORCE` environment contracts and the `-f` option
will continue to select the same update path and therefore receive identical
failure propagation.

## Orchestration

The update orchestrator will accumulate a simple failure status rather than
returning at the first recoverable error. Repository synchronization will
record failure and continue into finalization. Finalization will independently
record overlay, Shdeps, and merge failures, then always run cleanup and render
the final summary.

The launcher will return the orchestrator's status instead of replacing it
with zero. A failed run will end with `Done with errors in ...`; a successful
or warning-only run will retain the existing `Done in ...` text.

## Testing

Unit tests will prove that:

- a failed early stage does not prevent later stages from running;
- each required failure source produces a nonzero final status;
- multiple failures still complete cleanup and return nonzero;
- success and warning-only paths return zero;
- the public `dot update` launcher preserves the orchestrator status;
- failure output ends with the error-aware completion message.

The implementation adds no external command to the successful path and does
not affect shell or Neovim startup.
