# Codex Merge Hook Instance

This directory declares the `codex` merge-hook instance. Codex declarative
source families and private merge helpers live in this directory.

The executable hook implementation lives at
`~/.local/lib/dot/core/merge-hooks/codex.sh`.

## Integration ownership

`api.sh` resolves AgentGuard's native `codex/hooks.toml` generation and shared
`_shared/reconcile-hooks.jq` through shdeps. It converts the live and provider
TOML documents to JSON, lets AgentGuard replace only its historical generation,
then renders the result through the existing stable TOML serializer. AgentGuard
therefore owns Codex hook enablement, lifecycle tables, matchers, commands,
identity environment, timeouts, and retirement knowledge. Exact compatibility
behavior and tests live under `share/agentguard/integrations/` there.

Dotfiles owns the generic TOML merge, trust-hash refresh, cache invalidation,
profile rendering, and local settings in `config.d/`. Keeping those roles apart
lets any AgentGuard consumer reuse the native integration without inheriting
this repository's models, UI, MCP servers, profiles, or project policy.

The provider fragment and reconciler participate in the same cache signature as
every other source. Reconciliation preserves Codex's mutable `hooks.state`
records and user hooks before trust hashes are refreshed. If either provider
asset cannot be resolved, the hook reports a failed refresh and preserves the
whole last-known-good `~/.codex/config.toml`; local policy is deferred until the
security base is available again.

When changing an agent-specific hook, edit AgentGuard. When changing how Codex
state is safely merged, cached, or trusted on this fleet, edit the helper here.
