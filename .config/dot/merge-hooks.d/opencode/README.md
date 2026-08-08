# OpenCode

The `opencode` merge hook is only an installer. It resolves AgentGuard's
provider-owned `share/agentguard/integrations/opencode/agentguard.js` through
shdeps and copies those bytes to the global OpenCode plugin path
`~/.config/opencode/plugins/dotfiles-agentguard.js`.

All OpenCode event translation, command execution, session bookkeeping,
timeouts, and compatibility tests belong to AgentGuard. This directory does not
carry a local adapter copy. That ownership boundary matters because OpenCode
needs executable glue rather than a declarative hook fragment; letting the
consumer patch that glue would immediately fork its behavior.

## Installation safety

The provider source carries `// agentguard-managed:opencode-plugin` as its first
line. The hook updates only a regular, non-symlink target bearing that marker or
the legacy dotfiles marker used before this extraction. The legacy form is
migrated in place on the next successful install. An unmanaged file or symlink
at the same path is always preserved with a warning.

Missing or invalid provider source also preserves the installed target and is
reported as a failed refresh. That visibility matters on a cold bootstrap,
where there is no last-known-good plugin to preserve. A dependency can be
temporarily unavailable during a coordinated repository rollout; treating that
condition as an explicit disable request would remove protection at exactly the
wrong time. Unchanged bytes are not rewritten, so repeat `dot update` runs
preserve inode and modification time.

OpenCode discovers the global plugin directory automatically. No
`opencode.jsonc` entry is generated. A running OpenCode process keeps the plugin
version it loaded at startup, so changes take effect on the next process.

The shared agent-rule merge also writes OpenCode's native global rule target at
`~/.config/opencode/AGENTS.md`. OpenCode can fall back to Claude's global rules,
but relying on that optional compatibility mode would make rule loading depend
on an unrelated runtime remaining installed and enabled.
