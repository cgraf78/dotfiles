# Personal Scripts (`~/.local/bin/`)

Personal scripts deployed via `~/.dotfiles`. All are on PATH.
See also `CLAUDE-work.md` in this directory for work-specific scripts (if present).

## Claude Code Hooks

Hook scripts follow the naming convention `claude-hook-{event}[-{matcher}]`.
Each base script auto-delegates to a `-work` variant if one exists on PATH,
enabling layered composition without changing settings.json.

### `claude-hook-pre-bash` (PreToolUse, Bash)

Parses stdin JSON from the hook runner, exports `CMD_TRIMMED` (whitespace-
trimmed command), then runs base guards:
- **Blocks**: `rm -rf` on `/`, `~`, `$HOME`, or `..`
- **Warns**: any other `rm -rf` usage

Delegates to `claude-hook-pre-bash-work` if present.

### `claude-hook-post-bash` (PostToolUse, Bash)

Parses stdin JSON, exports `CMD_TRIMMED`. No personal post-actions currently.
Exists as the composition base for `-work` variant delegation.

### `claude-hook-post-edit` (PostToolUse, Edit|Write)

Parses stdin JSON, exports `FP` (file path). No personal post-actions currently.
Exists as the composition base for `-work` variant delegation.

### `claude-hook-session-end` (SessionEnd)

Auto-names Claude Code sessions by extracting user messages from the transcript
and calling `claude -p --model sonnet` in the background via `nohup`. Skips
sessions that already have a custom title. Delegates to `-work` variant if present.

## Delegation Pattern

```
settings.json → claude-hook-{event}
                  ↓
                  run base logic
                  ↓
                  command -v claude-hook-{event}-work
                  ├─ found → exec into it (CMD_TRIMMED/FP already exported)
                  └─ not found → exit 0
```

Work scripts receive `CMD_TRIMMED` or `FP` via exported env vars. They never
parse stdin — the base script already consumed it.
