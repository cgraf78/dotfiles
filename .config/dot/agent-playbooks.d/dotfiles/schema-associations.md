# Checkrun Schema Associations

<!-- agent-rule-id: checkrun-schema-association-review -->
<!-- agent-rule-trigger: Editing structured dotfiles config -->

When adding or modifying tracked JSON, JSONC, YAML, or TOML configuration files
in dotfiles, consider whether the file should be associated with a schema in
`~/.config/checkrun/associations.json`.

- Prefer official, first-party, SchemaStore, or dependency-owned schemas. Do
  not invent local schemas just to make a file look covered.
- Use generic match patterns for reusable conventions, such as `package.json`,
  `.github/workflows/*.yml`, or `.config/dot/merge-hooks.d/foo-*.json`.
- If a merge-hook source layer is valid by itself, associate the source layer
  with the generated target's schema rather than only the generated output.
- When a schema is useful for editor feedback but cannot be enforced offline,
  use the policy's advisory/editor-only shape instead of blocking lint.
- If adding a refreshable public schema, add or refresh the pinned payload under
  `~/.local/share/checkrun/schemas` with `checkrun schema refresh`.
- If no proper schema exists, leave the file unassociated and rely on parser,
  formatter, linter, or native validation tools.
