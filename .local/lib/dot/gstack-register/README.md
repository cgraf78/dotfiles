# GStack Registration

This directory owns dotfiles' lightweight gstack skill registration path.
Upstream gstack setup can build browser assets and install heavier runtime
pieces; dotfiles only needs `dot update` and the shdeps post hook to expose the
existing checkout's skills to installed agents.

## Dependency boundary

This registration path intentionally does **not** depend on Bun and must not run
upstream `gstack/setup` or `bun run gen:skill-docs`. Upstream's host-specific
`.agents/`, `.factory/`, and `.opencode/` skill trees are generated artifacts
and are not committed, so they are unavailable on a fresh lightweight checkout
without adding Bun as an installation dependency.

Instead, dotfiles materializes skills with Bash/Awk, applies the host transforms
it owns, and supplies each supported agent's runtime registration shape. This
preserves dependency-free `dot update` and shdeps hooks. Host-specific upstream
changes do not arrive automatically; parity changes must be reviewed and
implemented here without silently introducing Bun. The template-only
`gstack-claude` external-host skill is deliberately omitted because upstream
does not commit a resolved `claude/SKILL.md` that the dependency-free path can
consume.

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
- [`opencode.sh`](opencode.sh) writes an OpenCode-specific generated tree under
  `~/.gstack/dotfiles-opencode-skills`, allowlists supported frontmatter,
  rewrites runtime paths, omits the recursive Codex wrapper, and maintains
  OpenCode's runtime asset root without invoking Bun or upstream setup.
  The shell environment disables OpenCode's Claude skill fallback so this
  native tree is not advertised a second time under Claude-compatible names;
  CLAUDE.md rule fallback remains enabled.
- [`cache.sh`](cache.sh) implements the warm `dot update` fast path. Watch
  entries use mtimes to skip expensive validation only when every watched source
  and target is no newer than the cache; otherwise the slower fingerprint path
  validates and repairs the managed tree.

## Invariants

Generated skill directories are the source consumed by agents. Claude, Codex,
and Gemini point at the shared tree; OpenCode points at its host-transformed
tree. Runtime-root assets may link directly to non-skill files in the upstream
checkout, but registered `SKILL.md` files must come from a generated tree.

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
