# Hive Memory Config

This directory documents the local configuration instance for the standalone
Hive Memory tool. The tool implementation lives in the `cgraf78/hive-memory`
dependency repo; overlays or machine-local files own store-specific policy such
as storage roots and default store names.

## Boundaries

- Keep storage locations, default scopes, agent permissions, privacy policy, and
  offline behavior in `config.toml` when an overlay or local machine needs Hive
  Memory enabled.
- Keep startup context on the relevance strategy by default so durable
  preferences and project facts are automatic while incidents, references, and
  raw notes remain searchable instead of being injected into every session.
- Keep command implementation and schema behavior in the Hive Memory repo.
- Keep agent-runtime detection in the tracked dotfiles launcher
  [`.local/bin/hm`](../../.local/bin/hm).

Dotfiles installs the PATH-visible `hm` command through a shdeps hook. That
hook points `hm` at the dotfiles launcher, while the upstream binary remains
available behind an internal `hm-core` path.
