# Agent Rule Policy

This directory contains the dotfiles-owned policy consumed by the standalone
[`agent-rules-sync`](https://github.com/cgraf78/agent-rules-sync) provider. The split is
intentional:

- dotfiles owns the actual rule and playbook prose, overlay trust, source
  ordering, and the target profile selected for this fleet;
- `agent-rules-sync` owns generic manifest validation, playbook-route rendering,
  target adapters, managed-block publication, migration, stale cleanup, and
  uninstall behavior.

The small `agent-rules.sh` merge hook resolves the active families and trusted
playbooks into a versioned TSV manifest, writes it privately and atomically to
`$XDG_STATE_HOME/dot/agent-rules-sync-manifest-v1.tsv`, then runs
`agent-rules-sync --manifest`.
The manifest contains paths and routes rather than copying rule or playbook
prose. It is generated machine state, not a user-maintained config file.

Agent-specific merge hooks such as `claude`, `codex`, `gemini`, `muse`, and
`opencode` remain separate. They own settings, permissions, profiles, and
AgentGuard integration; this provider only publishes shared rule documents.

## Rule Sources

`rules.d/` contains concise, always-loaded Markdown fragments. Active files are
concatenated in family order by the provider. Use three-digit numeric prefixes
to make ordering explicit, and keep each `agent-rule-id` unique across rules
and playbooks.

Task-specific detail belongs in `~/.config/dot/agent-playbooks.d/`. The one
on-demand routing fragment contains
`<!-- agent-rules-sync-playbook-index -->`; the provider replaces that marker with
the ordered trigger and route list. Each playbook must declare exactly one
non-empty `<!-- agent-rule-trigger: ... -->` in its opening metadata block.
Playbook bodies are routed but are not copied into the always-loaded aggregate.

Overlay repositories may add ordered fragments or use `.replace` groups when a
rule family must be mutually exclusive. Dotfiles validates that playbooks are
tracked base files or exact links authorized by an active overlay before it
places them in the provider manifest.

## Target Policy

`targets.d/` selects the runtime files that receive the generated aggregate.
Each active `*.txt` file is a newline-delimited list of target files. Supported
path forms are absolute paths, `$HOME/...`, and `~/...`; the legacy `*.conf`
suffix remains accepted for existing overlays.

Use a `.replace` group for mutually exclusive machine profiles. Dotfiles
resolves these entries to absolute `target-file` records. The provider then
preserves unmanaged text, writes private files atomically, and removes only its
own managed blocks when a target becomes stale.

Generated runtime rule files and the resolved manifest are outputs. Edit the
source fragments, playbooks, or target policy here, then run `dot update` and
the relevant dotfiles tests.
