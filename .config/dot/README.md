# Dot Config

`~/.config/dot` contains configuration that drives the dotfiles manager itself.
Runtime code belongs under `~/.local/lib/dot`; generated configs belong in
their target-native config directories.

## Directories

- `overlays.d/` declares optional overlay repositories and their SSH aliases.
- `merge-hooks.d/` owns per-hook declarative config directories, merge source
  layers, and cron source files consumed by `dot update`.
- `merge-hooks.d/agent-rules/targets.d/` selects the generated agent rule
  target files for the current overlay profile. Dot resolves those inputs with
  trusted prose from `~/.config/agent-rules/` into a private generated
  manifest; the provider owns rendering and publication.

Related directories document their local conventions near the files they own.
For agent rule orchestration, `merge-hooks.d/agent-rules/README.md` documents
the target family and its boundary with the first-class content tree.

## Ordered Config Families

Dot config families use numeric prefixes when order matters:

- lower numbers run earlier
- higher numbers run later and can refine or override earlier policy
- overlay-provided files should generally use `80-` or higher inside shared
  ordered families so they run after base layers

Use descriptive names for what a layer does. Avoid requiring consumers to know
special words like `common` or `base`; when a config collection needs
mutual-exclusion, use the family `.replace` convention documented under
`merge-hooks.d/`.

## Boundaries

- Keep executable merge behavior in `~/.local/lib/dot/core/merge-hooks/*.sh`.
- Keep optional merge source data under
  `merge-hooks.d/<script-name>/`, matching the hook implementation name.
- Keep Checkrun policy in `.config/checkrun`, even when schema associations
  match files that live in `merge-hooks.d`.
- Keep overlay repository declarations in `overlays.d`.

This keeps `dot update` discoverable: dot-specific config is in `.config/dot`,
agent prose is in `.config/agent-rules`, shared code is in `.local/lib/dot`, and
generated app output is outside all three.

When adding or changing tracked JSON, JSONC, YAML, or TOML config in this
tree, check whether `~/.config/checkrun/associations.json` needs a schema
association. Use real upstream or dependency-owned schemas only; parser-only
formats and files without proper schemas should stay unassociated.
