# Dotfiles Merge Hooks

These are the application-specific hooks discovered by standalone `dot` from
the configured extension root. Declarative inputs remain under
`~/.config/dot/merge-hooks.d/<identity>/`; executable policy and private helper
code live here.

Each readable top-level `*.sh` file defines `merge()` with no arguments. The
filename supplies the public identity. A `*.serial.sh` file is a serial
barrier: `.serial` is stripped from its identity and sort key, and the runner
schedules it alone between parallel batches, so every barrier lengthens the
Configs stage. Reserve it for hooks that share mutable state with another hook,
and name it to sort after the ordinary hooks: the runner flushes the pending
parallel batch at each barrier, so a barrier sorted among other hooks splits
them into sequential batches. The dev overlay's `zz-codex-trust-prune`
barrier, for example, prunes the same `~/.codex/config.toml` its `codex` hook
merges, and must run after that merge instead of racing it. `cron.sh` stays
parallel because it is the only hook that reads or writes the user crontab, and
the top-level update lock already excludes concurrent `dot update` runs.

Hooks run in fresh Bash workers with private temporary storage. They use the
documented hook API and load client support through `dot_hook_source`. A hook
should return quietly when its application or configuration is absent. Base
hooks gate on `_dot_tool_present <identity>` from `lib/compat.sh`, which maps
only base identities. An overlay hook probes its own application instead,
either with the public `dot_tool_present` (one literal command or path) or
with the client probe helpers `lib/compat.sh` keeps for overlays:
`_dot_tool_any_command`, `_dot_tool_any_path`, and `_dot_tool_platform`. That
way base never lists an overlay's tools. Any nonzero hook status is recorded
as a configuration failure, later hooks still run, and the aggregate
`dot update` status is exactly 1.

The paired config tree contains user-editable source fragments. Do not move
executable helpers back under `.config/dot`: configuration is organized by the
program consuming it, while code is organized by the repository implementing
it.
