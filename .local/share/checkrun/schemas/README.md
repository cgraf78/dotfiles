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

The daily `Refresh Checkrun schemas` workflow runs the same refresh command and
publishes drift through one dedicated automation PR. A repository-scoped deploy
key synchronizes the final commit after the PR exists so the normal protected
dotfiles matrix runs; GitHub auto-merge lands the payload only after that gate
passes.
