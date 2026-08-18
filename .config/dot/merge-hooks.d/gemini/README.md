# Gemini Merge Hook

This directory declares the `gemini` merge-hook instance. The executable hook
at `~/.local/lib/dotfiles/merge-hooks.d/gemini.sh` resolves AgentGuard's native
`gemini/hooks.json` generation and AgentGuard's shared reconciler through
shdeps, then merges any optional local layers from `settings.d/`.

AgentGuard owns Gemini event names, tool matchers, commands, session identity,
and timeouts. Those are runtime compatibility facts, not personal dotfiles
policy, so their implementation and exact tests live under
`share/agentguard/integrations/gemini/` in AgentGuard.

There is currently no base JSON fragment in `settings.d/`: the complete native
hook fragment comes from the dependency. Overlays may add ordinary Gemini
settings here without copying the integration. The provider filter owns event
retirement and changed-command replacement. If either dependency asset is
temporarily unavailable, the hook reports a failed refresh and preserves the
whole live settings target rather than installing an unguarded partial config.
