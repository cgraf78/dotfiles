# Hive Memory Launcher

This directory owns the dotfiles-specific `hm` launcher. The generic Hive
Memory binary stays in the `cgraf78/hive-memory` dependency repo.

The launcher adds runtime context that is intentionally not part of the generic
tool:

- detects Claude, Codex, Gemini, or explicit `HIVE_MEMORY_AGENT_ID`
- derives a best-effort session id for direct agent shell commands
- infers the current project path for agent calls
- preserves the public command name as `hm` while executing the internal
  `hm-core` binary

Keep durable memory behavior, storage semantics, and CLI implementation in the
Hive Memory repo. Keep dotfiles/agent-session inference here so other users of
the generic binary do not inherit this environment policy.
