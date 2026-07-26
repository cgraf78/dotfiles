# Merge Hook Implementations

This directory contains the executable merge hook instances run by `dot update`.
Each readable `*.sh` file is a hook implementation. The filename stem is the
hook instance name.

## Instance Contract

- `dot update` discovers hook instances by enumerating readable
  `~/.local/lib/dot/core/merge-hooks/*.sh` files.
- A hook named `foo.sh` may consume declarative config from
  `~/.config/dot/merge-hooks.d/foo/`.
- The matching config directory is optional. Hooks for tools that are not
  configured on a machine should return without producing changes.
- Top-level hook instance names are unprefixed and should match between this
  directory and `~/.config/dot/merge-hooks.d/` when a config directory exists.
- Numeric prefixes belong inside ordered config families, not on top-level hook
  instance scripts or config directories.

Hook discovery is sorted by script filename because the runner needs a
deterministic stream, but independent hooks may run in parallel within that
stream. Hooks must not rely on another hook running first. Shared values should
live in a common helper or generated target rather than in implicit hook
ordering.

Hooks should stay parallel unless they have a known shared-state hazard that is
unsafe with another merge hook. Add those exceptions to `_merge_hook_is_serial`
in `../merges.sh` with a comment naming the specific hazard. The current
exception is `cron`, because it read-modify-writes the singleton user crontab
and crontab installation replaces the whole table. Serial hooks keep their
lexical position: the runner drains any pending parallel hooks before running
the serial hook, then starts a new parallel batch after it. Set
`DOT_MERGE_JOBS` to control the maximum number of concurrent hooks in each
parallel batch. When unset, merge hooks inherit `DOT_UPDATE_JOBS`, which
defaults to the host CPU count.

## Config Coupling

The sibling config tree under `~/.config/dot/merge-hooks.d/` contains
declarative inputs owned by each hook. This directory owns code that applies
those inputs. Keep those responsibilities separate:

- put application-specific merge behavior in the hook script here
- put tracked, user-editable source fragments under the matching config
  directory
- use `_merge_hook_source`, `_merge_hook_family`, and
  `_merge_hook_family_files_matching` from `../merge-hooks.sh` to resolve config
  paths
- document each configured hook instance with a README in its config directory

For example, `agent-rules.sh` reads
`~/.config/dot/merge-hooks.d/agent-rules/rules.d/` and
`~/.config/dot/merge-hooks.d/agent-rules/targets.d/`. Overlays can contribute
additional family layers under those same paths without changing this
implementation directory.

## Hook Shape

Each hook script should define a `merge` function. The merge runner sources each
script in isolation, then calls `merge` when it exists.

Hooks should be quiet when they have no applicable config. When a hook writes a
generated file, prefer the shared helpers in `../merge-hooks.sh` and
`../merge-block.sh` so temp-file safety, family ordering, and managed block
replacement stay consistent across hook instances.
