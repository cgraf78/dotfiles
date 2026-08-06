# Muse Merge Hook

This directory declares the `muse` merge-hook instance. Its declarative source
family is `settings.d/` in this directory.

The executable hook implementation lives at
`~/.local/lib/dot/core/merge-hooks/muse.sh`.

Modeled after `claude` (`settings.d/10-agentguard.json`) and `codex`
(`config.d/10-settings.toml`) with `AGENTGUARD_NAME=muse`. Muse currently
supports `SessionStart`/`PreToolUse`/`PostToolUse`/`Stop`/`UserPromptSubmit`;
`Notification` and `SessionEnd` are Claude-only and are intentionally omitted
until Muse adds support (they previously caused `UnsupportedEvent` warnings).
