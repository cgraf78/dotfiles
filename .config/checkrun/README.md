# checkrun

This directory owns this dotfiles checkout's `checkrun` policy:

- fallback formatter and linter configs used when a project does not provide
  local tool policy
- ignore files that decide which Checkrun phases should skip a path
- schema association policy that maps local files to validation schemas

## Files

Tool fallback configs:

```text
biome.json                # JSON/CSS/JS/TS format + lint
checkmake.ini             # Makefile lint
clang-format              # C/C++ format
cmake-format.py           # CMake format + lint
golangci-lint.yml         # Go lint
hadolint.yaml             # Dockerfile lint
php-cs-fixer.php          # PHP format
rubocop.yml               # Ruby format + lint
ruff.toml                 # Python format + lint
rumdl.toml                # Markdown format + lint
rustfmt.toml              # Rust format
selene.toml               # Lua lint
shellcheckrc              # Shell lint
shfmt.toml                # Shell format
stylua.toml               # Lua format
taplo.toml                # TOML format + lint
typos.toml                # spelling lint
yamlfmt.yaml              # YAML format
```

Ignore policy:

```text
ignore                    # all-phase ignore patterns
format-ignore             # formatter-only ignore patterns
schema-ignore             # schema-validation-only ignore patterns
spell-ignore              # spelling-only ignore patterns
tool-ignore               # backend-linter-only ignore patterns
```

Schema policy:

- `associations.json` is the single source of truth for schema matches.
- `.local/share/checkrun/schemas/*.schema.json` stores pinned copies of public
  schema payloads used by non-editor tooling; see the
  [`schema payload README`](../../.local/share/checkrun/schemas/README.md).
- `shdeps dep-file cgraf78/checkrun lib/checkrun/schemas/schema_policy.py` is
  the shared policy interpreter. It expands match patterns, resolves local
  schema paths, and emits editor-facing LSP schema associations with
  `--lsp-schemas`.
- `shdeps dep-file cgraf78/checkrun lib/checkrun/schemas/schema-lint.py`
  validates files through the shared interpreter for `autolint`.
- `shdeps dep-file cgraf78/checkrun share/checkrun/schemas/associations.schema.json`
  validates the association policy shape. Dotfiles owns the policy instance;
  `checkrun` owns the schema because it owns the interpreter semantics.

When adding or changing tracked JSON, JSONC, YAML, or TOML config files, check
whether the file should be represented in `associations.json`. Prefer official,
SchemaStore, first-party, or dependency-owned schemas; do not invent local
schemas just to cover a file.

## House Style

These fallback configs share one style, but each tool spells it in its own
native format, so the values cannot live in a single file. This section is the
authoritative source they must mirror; when editing a config, match these
unless the language convention overrides them.

- **Line width: 100 columns** — `biome.json`, `clang-format`, `ruff.toml`,
  `rustfmt.toml`, `stylua.toml`, `taplo.toml`.
- **Indentation: 2 spaces** — `biome.json`, `clang-format`, `cmake-format.py`,
  `shfmt.toml`, `stylua.toml`, `taplo.toml`, `yamlfmt.yaml`.

Deliberate exceptions:

- `ruff.toml` (Python) and `rustfmt.toml` (Rust) indent **4 spaces**, the
  established convention for those languages.
- `cmake-format.py` wraps at **88 columns** rather than 100. If that is
  unintentional drift rather than a deliberate choice, align it to 100.

## Resolution Policy

For each supported tool, Checkrun first looks for a project-local config by
walking up from the target file's directory. When one is found, the tool's
native discovery is used when it is path-stable; otherwise Checkrun passes the
absolute config path explicitly.

When no project-local config exists, the matching file from this directory is
passed explicitly as the fallback. Set `CHECKRUN_CONFIG_DIR` to override this
root for a single run; it defaults to `~/.config/checkrun`.

Ignore policy is phase-specific. `ignore` is the compatibility escape hatch for
files that should skip every phase. Prefer `format-ignore`, `spell-ignore`,
`schema-ignore`, and `tool-ignore` when a file should skip only one part of the
pipeline. This keeps schema validation available for vendored or generated
configuration data even when formatting or prose checks would create churn.

Parser-only checks such as `php -l`, `git config --file`, `crontab -T`, and
`systemd-analyze verify` intentionally have no fallback style config.
Opinionated tools such as `google-java-format` also do not need one.

The schema payloads live under `.local/share`, not `.cache`, because they are
tracked runtime data. They should survive cache cleanup and should not require
network access from hooks, CI, or editors.

When a schema is public API owned by another shdeps-managed dependency, keep
the payload in that dependency repo and add `"dependency": "owner/repo"` beside
the repo-relative `"schema"` path. The shared interpreter resolves that through
`shdeps dep-file`, so dotfiles only owns the association policy.

## Matching Policy

Patterns in `associations.json` may be written as home-relative dotfiles paths
or repo-local convention names such as `pyproject.toml`, `Cargo.toml`, or
`docker-compose.yml`. Consumers expand each pattern in three ways:

- the home-relative path, such as `.config/dot/merge-hooks.d/foo.json`
- the absolute `$HOME` path
- a recursive `**/` match for copied checkouts and overlay worktrees

Keep patterns generic and convention-based. Prefer family-wide patterns such as
`.config/dot/merge-hooks.d/claude/settings.d/*.json` and
`.config/dot/merge-hooks.d/claude/settings.d/*.replace/*.json` over naming
individual personal, work, or future layer files.

## Merge Config Layers

Schema associations in `.config/dot/merge-hooks.d` target source layer files
for generated configs, not the `*.sh` hooks or hook-private helper scripts.
SchemaStore usually matches the final target path, but these source files use
dotfiles-specific names so merge hooks can compose personal, work, and
host-specific layers. If each layer is valid by itself, associate the layer
directly with the target's public schema.

When a layer cannot yet satisfy a public schema, keep the association with
`"enforce": false`. That preserves editor help and documents the intended
schema without blocking `autolint`.

Whenever a new merge-hook source layer is added, include schema association
review in the same change. If no proper schema exists, leave the file
unassociated and rely on parser/linter/native validation instead.

## Boundaries

- `.config/checkrun` owns this checkout's Checkrun policy and documentation.
- `.config/dot/merge-hooks.d` owns merge hooks, their private helpers, and
  merge source layers.
- `.config/dot/overlays.d` owns overlay repository configuration.
- `.local/share/checkrun/schemas` owns pinned public schema payloads.
- Dependency repos own schema payloads that are part of their public API.
- The `checkrun` dependency repo owns validation code and the association
  policy schema.

Do not scatter downloaded schemas under merge hooks, overlays, editor config,
or generic cache directories.
