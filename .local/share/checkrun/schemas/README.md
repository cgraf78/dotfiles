# Pinned Schema Payloads

This directory contains tracked JSON schemas used by `autolint` and other
non-editor tooling. Most files are pinned copies of public schemas; a small
number are dotfiles-owned schemas for local policy files. They are runtime data,
not cache data: hooks and CI should be able to validate files without network
access.

## Policy

- Association policy lives in `~/.config/checkrun/associations.json`.
- Validation code and the association policy schema live in the `checkrun`
  dependency repo.
- Pinned public schema payloads and dotfiles-owned local schemas live here.

When refreshing a public schema, keep the filename stable when the association
still means the same schema. Use a new filename only when the schema identity or
major compatibility contract changes.
