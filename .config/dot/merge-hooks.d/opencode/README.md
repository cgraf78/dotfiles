# OpenCode

The `opencode` merge hook installs
[`agentguard.js`](agentguard.js) as the global OpenCode plugin
`~/.config/opencode/plugins/dotfiles-agentguard.js`.

The source and generated file carry a stable ownership marker. The hook updates
or removes only a regular, non-symlink target with that marker; an unmanaged
file or symlink at the same path is preserved with a warning. Unchanged bytes
are not rewritten, so repeat `dot update` runs preserve the file's inode and
modification time.

OpenCode discovers the global plugin directory automatically. No
`opencode.jsonc` entry is generated. A running OpenCode process keeps the plugin
version it loaded at startup, so changes take effect on the next process.

The adapter also supplies `AGENTGUARD_NAME=opencode` and the active session ID
through OpenCode's `shell.env` callback. This gives direct `hm remember` and
`hm note` commands the same Hive Memory receipt/reminder identity available in
Claude and Codex, while the shared `hm` launcher remains the sole owner of
`HIVE_MEMORY_*` translation.

The shared agent-rule merge also writes OpenCode's native global rule target at
`~/.config/opencode/AGENTS.md`. OpenCode can fall back to Claude's global rules,
but relying on that optional compatibility mode would make rule loading depend
on an unrelated runtime remaining installed and enabled.
