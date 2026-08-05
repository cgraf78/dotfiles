# Core Runtime

`core/` owns the `dot` command runtime and the shared shell loading helpers used
by bootstrap, shell startup, and health checks.

## Responsibilities

- repository discovery for the base bare repo and overlays
- update, fetch, push, status, diff, and cron orchestration
- merge-hook execution
- bootstrap-safe shell loading
- shdeps asset loading for sourceable dependency APIs
- shdeps update progress rendering
- doctor checks, with section modules under [`doctor/`](doctor/README.md)
- terminal UI helpers

The public command surface is `~/.local/bin/dot` and `~/.local/bin/dotbootstrap`.
Callers should source `init.sh` rather than individual implementation files.
Small hook and shell-startup integrations may source `shdeps-assets.sh` when
they need a file from a shdeps-managed dependency repo.

The basic runtime is split into focused helper modules:

- `constants.sh` owns the base repo constants and quiet-mode default.
- `log.sh` owns color constants and quiet-aware logging helpers.
- `progress-ui.sh` owns live `dot update` progress rendering and summary text.
- `run.sh` owns command execution helpers that capture logs and tick live UI.
- `resources.sh` owns interruption-safe child, process-group, descriptor, and
  temporary-path cleanup. Parallel callers must register through this API so
  cancellation finishes owned work before update-lock release.
- `platform.sh` owns platform and privilege helpers.
- `overlays.sh` owns overlay config parsing and active-overlay discovery.
- `merge-block.sh` owns marked-block assembly for generated configs that need
  hand-managed content preserved ahead of dot-managed blocks.
- `families.sh` owns ordered fragment-family discovery: direct files aggregate,
  immediate `.replace` groups select one lexical winner, and consumers receive
  the final source stream without duplicating structural policy.
- `merge-hooks.sh` owns common merge-hook mechanics: tracked source path
  resolution, parser-tool probes, sibling-temp writes, and the generic JSON
  layer merge shape. Hooks keep target-specific policy local but use these
  helpers for repeated file-safety behavior.
- `merges.sh` owns merge-hook discovery from core implementation scripts,
  progress labels, output capture, and verbose/default rendering.

[`repos/`](repos/README.md) owns base-plus-overlay repo-set behavior.
`repos/api.sh` is the source point for command dispatch and update
orchestration; its focused modules keep repo config, bare-vs-overlay Git
invocation, pull behavior, overlay linking, dirty-state normalization, and
simple fetch/push/status/diff commands separate. Call its helpers rather than
reimplementing overlay loops in the launcher.

`update-lock.sh` serializes each `dot update` before shdeps bootstrap can mutate
machine state. It uses an owner-recorded portable directory lock, preserving
ownership across the self-update re-exec and reclaiming only stale owners.

`update.sh` owns the `dot update` lifecycle after bootstrap-visible flags have
been pre-scanned by the launcher: update flag parsing, cron dirty-worktree
handling, repo sync, infrastructure re-exec, dependency updates, overlay
linking, merge hooks, and final cleanup. Keep those steps together so subtle
state such as `--cron`, `--skip-pull`, and `DOT_REEXEC` can be reviewed as one
flow.

`shdeps-ui.sh` adapts shdeps' `SHDEPS_PROGRESS=jsonl` stream into the generic
dot UI primitives. shdeps owns dependency update behavior and event vocabulary;
dot owns grouping, summaries, verbose rendering, and live terminal updates.
Non-fatal warning items retain both their warning count and actionable detail;
they must not be folded into the current dependency count.

`doctor.sh` is the public doctor source point. It lazily loads the focused
modules under `doctor/`, which share a small private result API for section
output and summary accounting.

## Update Flow

`dot update` pulls the base repo and active overlays, links overlay files, runs
dependency updates, runs merge hooks, and refreshes generated state.

`DOT_UPDATE_JOBS` is the top-level concurrency knob for update subwork that can
run in parallel. It defaults to the host CPU count. `DOT_MERGE_JOBS` and
`SHDEPS_JOBS` remain narrower overrides; when unset, dot gives both the
resolved `DOT_UPDATE_JOBS` value.

If the pull changes dot infrastructure such as `.local/lib/dot/` or
`.local/bin/dot`, the command re-execs itself so the rest of the update uses
the new implementation.

Overlay files that replace base files are marked `--skip-worktree` in the base
repo, preventing phantom dirty state while the overlay owns that path.

## Bare Repo Notes

The base repo is bare with `$HOME` as its work tree. Run `dot` commands from
`$HOME`; the PATH-visible `git` launcher provides raw Git access to the base
repo from `$HOME` and non-repo descendants.

The PATH-visible `git` and `sley` launchers handle the local bare `$HOME` repo
context by setting `GIT_DIR` and `GIT_WORK_TREE` before entering the generic
tools. Use plain `git` for raw Git operations and plain `sley` for readiness
workflows.
