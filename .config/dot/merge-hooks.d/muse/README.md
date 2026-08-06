# Muse Merge Hook

This directory declares the `muse` merge-hook instance. Its declarative source
family is `settings.d/` in this directory.

The executable hook implementation lives at
`~/.local/lib/dot/core/merge-hooks/muse.sh`.

Modeled after `claude` (`settings.d/10-agentguard.json`) and `codex`
(`config.d/10-settings.toml`) for full AgentGuard parity: Muse gets the same
`SessionStart`/`PreToolUse`/`PostToolUse`/`Notification`/`Stop`/`SessionEnd`/`UserPromptSubmit`
lifecycle hooks, with `AGENTGUARD_NAME=muse`.
