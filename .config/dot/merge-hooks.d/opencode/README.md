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
