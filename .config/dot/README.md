# Dot Config

`~/.config/dot` contains declarative configuration consumed by the standalone
`dot` manager and the dotfiles-owned extensions it runs. Executable client
policy belongs under `~/.local/lib/dotfiles`; generated configs belong in their
target-native config directories.

## Directories

- `config` enables the dotfiles extension root and optional Shdeps provider and
  sets the fleet's initial no-selector fallback to `default_profile=dev`. This
  preserves the pre-refactor full environment during rollout; a later,
  separately reviewed fleet change can switch the fallback to `base` after
  explicit selectors are ready.
  This development fleet sets `shdeps_update_policy=latest`, allowing a valid
  user-owned `~/git/shdeps` checkout for `cgraf78/shdeps` to follow its current
  revision even when it is newer than Dot's reviewed fallback lock. Without a
  valid local checkout, the pinned installer remains the bootstrap trust anchor
  while the managed release path checks for and installs the newest available
  release on every update. Network or metadata failures retain Shdeps' existing
  last-known-good behavior and must not be reported as reaching the latest
  release. The standalone runtime parses this file before loading extensions or
  the dependency provider.
- `profiles.d/` defines the additive `base`, `editor`, and `dev` profiles. A
  profile contains overlay names only; the root repository is always active.
- `profile-selectors.d/` contains reviewed non-sensitive selectors. Ignored
  machine-local selectors live in `profile-selectors.local.d/`; private
  selectors may be contributed by the optional personal overlay.
- `overlays.d/` declares overlay repositories. A selected eligible descriptor's
  same-stem `.ssh` companion is consumed by the client-owned pre-sync hook
  before a private overlay clone is attempted.
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

- Keep executable merge behavior in
  `~/.local/lib/dotfiles/merge-hooks.d/*.sh`.
- Keep optional merge source data under
  `merge-hooks.d/<script-name>/`, matching the hook implementation name.
- Keep Checkrun policy and schema associations in the development overlay,
  even when they match files contributed to shared merge families.
- Keep overlay repository declarations in `overlays.d`.
- Keep reusable profile membership in `profiles.d` and host/user choices in the
  appropriate selector directory. `default_profile` is only the no-match
  fallback; selectors override it. Do not branch application configuration on a
  profile name.

This keeps `dot update` discoverable: dot-specific config is in `.config/dot`,
agent prose is in `.config/agent-rules`, dotfiles-owned code is in
`.local/lib/dotfiles`, and generated app output is outside all three. The
standalone engine itself remains checkout-relative and is not copied into this
client tree.

When adding or changing structured config, update the owning overlay's schema
associations when appropriate. Use real upstream or dependency-owned schemas
only; parser-only formats and files without proper schemas stay unassociated.
