# Repo Runtime

`core/repos` owns every `dot` operation that treats the base bare repo and
active overlay repos as one repo set.

The public source point is `api.sh`; callers should not source individual
modules. The split exists to keep the main invariants reviewable:

- the base dotfiles repo is bare and must be invoked through `$GIT`
- overlays are normal Git repos and must use `git -C <path>`
- simple commands only touch repos that already exist locally
- pull/update may clone missing overlays when their configured remote is
  available, or when their deploy key is available for deploy-key overlays
- overlay links shadow base files with symlinks and `skip-worktree`
- cron dirty-state repair must only fix content-clean or remote-matching files

## Public Surface

`api.sh` exports the repo helpers used by `dot`, `dotbootstrap`, and core tests:

- `_repo_fetch_all`, `_repo_push_all`, `_repo_diff_all`, `_repo_status_all`
- `_repo_pull_all`
- `_link_overlays`
- `_is_worktree_dirty`, `_try_resolve_dirty`, `_normalize_filtered`
- `_ensure_repo_config`

Everything else is private implementation detail. Keeping the public surface
small matters because these helpers are sourced into long-running shell
contexts during tests and updates; accidental global state is harder to audit
when every helper is effectively public.

## Modules

- `config.sh` applies repo policy and repairs old base remote URLs.
- `git.sh` centralizes base-vs-overlay repo iteration and Git invocation.
- `dirty.sh` handles dirty checks, out-of-band write repair, and filter normalization.
- `pull.sh` owns base/overlay pull behavior and update progress reporting.
- `overlays.sh` owns overlay symlink manifests and `skip-worktree` handling.
- `commands.sh` owns fetch, push, diff, and status command wrappers.

## Update Flow

`dot update` calls `_repo_pull_all` before dependency updates and merge hooks.
That helper intentionally does only repo synchronization:

1. apply repo config and normalize content-clean dirty paths
2. restore any base files currently hidden by overlay symlinks
3. pull the base repo
4. clone or pull pull-eligible overlays, running independent overlay repo syncs
   in parallel up to `DOT_UPDATE_JOBS`
5. report one repo-stage summary back to the update dashboard

After that, update calls `_link_overlays` to recreate overlay symlinks and
re-apply `skip-worktree` for tracked base files shadowed by overlays.

Overlay linking itself stays serial. Overlay discovery order defines
last-overlay-wins behavior for conflicting files, and the link step writes one
shared manifest under `${XDG_STATE_HOME}/dot/overlay-links` when
`XDG_STATE_HOME` is absolute, falling back to
`~/.local/state/dot/overlay-links`.

## Edge Cases

Missing overlays are skipped by `fetch`, `push`, `status`, and `diff`; those
commands should stay cheap and should never clone a repo as a side effect.
Only pull/update may clone a missing overlay, and only when the overlay has a
URL and any required deploy key is present. Optional overlays are attempted
when active, but missing deploy keys and clone or pull failures are skipped so
private overlays can be declared in the base repo without breaking machines
that lack access. Required overlays report missing keys and failed syncs.

The overlay manifest in the selected state directory is the cleanup authority
for symlinks created by older runs. If an overlay file disappears, the manifest
lets `_link_overlays` remove the stale home symlink and restore the base tracked
file when one exists. On the first run after selecting an XDG state directory,
dot safely consumes and removes the old HOME-default manifest after writing the
new one so cleanup ownership is not lost during migration.

Before changing a home symlink or `skip-worktree` bit, linking atomically
publishes a private sibling `overlay-links.pending` manifest. It contains the
selected and legacy authority plus every exact generated link the run may
create. An interrupted run leaves that write-ahead authority in place; the next
run accepts any recorded owner only when the live symlink exactly matches dot's
generated target. The pending and adopted legacy manifests are removed only
after the selected manifest is replaced successfully. Unsafe pending paths
(including symlinks, non-regular files, and group/world-accessible files) stop
linking before it can mutate home or Git index state.

Cron dirty-state repair is deliberately narrow. `_try_resolve_dirty` only
checks out files that exactly match `origin/main` after fetch; local edits that
differ from the remote must keep blocking cron updates.

When adding repo behavior, prefer putting durable policy in `config.sh`,
repo-set traversal in `git.sh`, and command-specific behavior in the module
that owns the user-visible operation.
