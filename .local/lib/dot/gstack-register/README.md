# GStack Registration

This directory owns dotfiles' lightweight gstack skill registration path.
Upstream gstack setup can build browser assets and install heavier runtime
pieces; dotfiles only needs `dot update` and the shdeps post hook to expose the
existing checkout's skills to installed agents.

Public API lives in [`api.sh`](api.sh):

- `dot_gstack_dir` returns the upstream checkout path
  (`~/.local/share/garrytan/gstack`).
- `dot_gstack_register_all` refreshes generated skills and agent registrations.
- `dot_gstack_unregister_all` removes only dotfiles-managed registrations.

Callers should source `api.sh`, not the implementation modules. The two normal
callers are the gstack shdeps post hook and the `gstack` merge hook. The
merge hook is intentional: shdeps hooks run only when dependencies change, while
`dot update` is the regular fleet-wide repair path.

## Excluding skills

Upstream ships every skill it has, and each registered skill spends description
text in every agent session's skill budget. `~/.config/dot/gstack-skills-exclude`
(override with `DOT_GSTACK_SKILL_EXCLUDE_FILE`) lists skills to leave
unregistered, one name per line, `#` for comments. Bare (`browse`) and
prefixed (`gstack-browse`) spellings both work.

Excluding a skill drops it from the source inventory, so the existing
stale-target cleanup removes any registration it already had — no separate
uninstall step. An entry matching no upstream skill is warned about rather than
ignored, because it otherwise fails open and looks like a no-op.

## Modules

- [`paths.sh`](paths.sh) defines shared paths, logging adapters, checksums,
  agent availability probes, and cache constants.
- [`source.sh`](source.sh) scans the upstream checkout for source skills and
  caches that inventory for one registration run. It also owns
  `_dot_gstack_skill_dir_is_skipped`, the single decision point for which
  upstream directories are registrable, covering both the built-in non-skill
  directories and the user exclude list.
- [`managed.sh`](managed.sh) recognizes and safely removes only targets dotfiles
  owns. This protects unrelated user-installed skills when names collide.
- [`migration.sh`](migration.sh) repairs the old install shape where `~/.gstack`
  was a symlink to the checkout. It moves only known runtime state entries so
  source directories are not accidentally drained into durable state.
- [`generated.sh`](generated.sh) writes the shared generated skill tree under
  `~/.gstack/dotfiles-skills`. Generated skills normalize names to `gstack-*`
  and rewrite old Claude runtime paths to the actual checkout.
- [`targets.sh`](targets.sh) links generated skills into Claude, Codex, and
  Gemini locations, and prunes stale managed registrations.
- [`cache.sh`](cache.sh) implements the warm `dot update` fast path. Watch
  entries use mtimes to skip expensive validation only when every watched source
  and target is no newer than the cache; otherwise the slower fingerprint path
  validates and repairs the managed tree.

## Invariants

Generated skill directories are the single source consumed by agents. Claude,
Codex, and Gemini registrations should point at that shared tree rather than
copying or linking directly to upstream source skills.

Removal must be conservative. A path can be deleted only when it is a symlink to
managed gstack content, has a dotfiles managed marker, or carries the generated
source marker in `SKILL.md`.

The exclude list is a registration input even though it lives outside the
checkout, so it is both watched and hashed into the source fingerprint. Without
that, a warm `dot update` would keep serving the pre-edit registration set.

Cache correctness is repair-oriented, not byte-for-byte validation. The fast
path is allowed to skip steady-state work, but missing targets, stale managed
targets, changed source skills, agent availability changes, and newer watched
files must fall back to a full registration pass.
