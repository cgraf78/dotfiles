# OpenCode AgentGuard Hooks Design

> **Superseded (2026-08-07):** This document records the original dotfiles-owned
> implementation. The reusable adapter, runtime contract, and behavioral tests
> now live under `share/agentguard/integrations/opencode/` in AgentGuard.
> Dotfiles retains only the thin provider-asset installer documented in
> `.config/dot/merge-hooks.d/opencode/README.md`; paths and ownership statements
> below are historical and must not guide new work.

## Goal

Install a source-managed global OpenCode plugin from the dotfiles merge-hook
system so OpenCode receives the AgentGuard protections and lifecycle hooks that
its callback model can represent.

## Scope and Constraints

This change belongs to the public dotfiles repository. It reuses the
`agent-hook-*` executables installed by the `cgraf78/agentguard` dependency and
does not require an AgentGuard release.

OpenCode's supported global extension point is the automatically loaded
`~/.config/opencode/plugins/` directory. The integration therefore installs one
JavaScript protocol adapter and does not change `opencode.jsonc`.

The adapter covers:

- prompt submission;
- session start, stop, and end;
- permission notifications;
- pre- and post-execution handling for Bash, edit, and MCP tools.

OpenCode loads plugins only when a process starts. A later `dot update` changes
the plugin used by the next OpenCode process, not one that is already running.

## Files

- `.config/dot/merge-hooks.d/opencode/README.md` documents the source and
  generated target.
- `.config/dot/merge-hooks.d/opencode/agentguard.js` is the authoritative
  OpenCode plugin.
- `.local/lib/dot/core/merge-hooks/opencode.sh` installs or prunes the managed
  plugin.
- `~/.config/opencode/plugins/dotfiles-agentguard.js` is generated and must not
  be edited directly.
- `.local/lib/dot/tests/core/merges.sh` covers installation, ownership, pruning,
  and idempotence.
- `.local/lib/dot/tests/opencode-agentguard-test` exercises the adapter with
  fixture hook executables and Node.
- `.local/lib/dot/core/doctor/agent-hooks.sh` reports a missing or invalid
  installed adapter when `opencode` is available.

The source and generated plugin begin with the stable ownership marker
`// dot-managed:opencode-agentguard-plugin`. The unique target name avoids
claiming a generic file such as `agentguard.js` that the user may already own.

## Merge-Hook Behavior

The `opencode` merge hook resolves its source relative to its own checkout, with
`DOT_OPENCODE_SOURCE_DIR` available for fixture tests. It creates
`~/.config/opencode/plugins/` when the source exists.

The hook manages only `dotfiles-agentguard.js`:

- If the target is absent, install the source atomically.
- If the target is a regular, non-symlink file with the ownership marker,
  update it atomically when its bytes differ.
- If that managed target already has identical bytes, return before creating a
  temporary file or renaming anything.
- If the target is a symlink or lacks the marker, warn and preserve it.
- If the source is absent, remove the target only when it is a regular,
  non-symlink file with the marker.

Atomic writes use a sibling temporary file and rename. An unchanged second run
must preserve bytes, inode, modification time, and every unrelated plugin, and
must leave no temporary sibling. Repeated runs can never add a configuration
entry or duplicate because the integration installs one fixed file and does not
edit OpenCode configuration.

## Adapter Execution Contract

The plugin runs hook commands through a fixed Bash bootstrap:

```text
bash -c 'exec "$1"' agentguard /absolute/path/to/agent-hook-...
```

No payload value is interpolated into shell text. The extra Bash process loads
`BASH_ENV=~/.config/shell/env-noninteractive.sh` when available, preserving the
non-interactive AgentGuard environment used by other runtimes. The executable
resolves first from `~/.local/bin`, then from `PATH`.

Every invocation:

- runs in the plugin-provided `directory`, except Bash tool hooks with a
  `workdir`, which run in OpenCode's effective absolute working directory;
- inherits the OpenCode environment;
- sets `AGENTGUARD_NAME=opencode`;
- sets `AGENTGUARD_SESSION_ID` to the OpenCode session ID;
- sends one JSON payload on standard input;
- captures standard output and standard error;
- kills the timed-out hook's process group on POSIX so descendants cannot
  outlive the denied invocation, with a direct-child fallback on Windows;
- applies the same process-tree cleanup if a hook closes standard input before
  consuming its payload.

The production timeout matrix mirrors the existing AgentGuard integrations:

| Hook | Timeout |
| --- | ---: |
| pre-Bash | 600 seconds |
| post-Bash | 120 seconds |
| post-edit | 60 seconds |
| session-end | 30 seconds |
| all other adapter hooks | 10 seconds |

Tests override these values with short timeouts.

If an executable is absent, the plugin logs one notice per session and treats
that hook as unavailable. This permits bootstrap before AgentGuard has been
installed, matching `dot doctor`'s advisory missing-hook behavior. Once a
protected pre-hook executable is found, launch errors, timeouts, non-protocol
exit statuses, and malformed non-empty successful output fail closed.

Whitespace-only output is empty context. Non-empty successful output must be
valid JSON. Context is read from `context` first, then
`hookSpecificOutput.additionalContext`.

Exit status 2 from a protected pre-hook is an intentional denial. The adapter
throws before OpenCode executes the tool and uses trimmed standard error as the
reason, with parsed context and standard output as fallbacks. Post-tool,
notification, and lifecycle failures are logged and cannot retroactively fail
completed work.

OpenCode launches Bash tools separately from hook subprocesses. The adapter's
`shell.env` callback therefore sets `AGENTGUARD_NAME=opencode` and the supplied
OpenCode session ID for the tool shell itself. It preserves unrelated
environment entries and masks an inherited AgentGuard session ID with an empty
overlay value when OpenCode does not supply one. That explicit mask matters
because OpenCode merges the hook output over its parent environment after the
callback. The dotfiles `hm` launcher consumes these generic keys and owns
translation to `HIVE_MEMORY_AGENT_ID` and `HIVE_MEMORY_SESSION_ID`.

## Exact Payload Translation

Payloads use AgentGuard's existing keys: `session_id`, `cwd`,
`hook_event_name`, `tool_name`, `tool_input`, `tool_response`, and `prompt`.
The adapter pins these event names:

| Adapter action | `hook_event_name` |
| --- | --- |
| session start | `SessionStart` |
| prompt submit | `UserPromptSubmit` |
| pre-tool | `PreToolUse` |
| post-tool | `PostToolUse` |
| permission notification | `PermissionRequest` |
| response stop | `Stop` |
| session finalization | `SessionEnd` |

Tool translation is explicit:

| OpenCode tool | AgentGuard `tool_name` | AgentGuard `tool_input` |
| --- | --- | --- |
| `bash` | `Bash` | `command`, optional `timeout` and `workdir` |
| `edit` | `Edit` | `file_path`, `old_string`, `new_string`, `replace_all` |
| `write` | `Write` | `file_path`, `content` |
| `apply_patch` or `patch` | `Edit` | `patch` from `patchText` or `patch` |
| configured MCP tool | `mcp__server__tool` | original arguments |

The adapter may retain original camel-case arguments alongside these canonical
keys, but the snake-case AgentGuard keys are authoritative.

Bash hook payloads resolve an absolute `cwd` from the plugin directory and the
optional relative or absolute `workdir`. Bash post payloads map OpenCode's
result `output` to `tool_response.stdout`. The production
`metadata.exit` field becomes `exit_code`; a null signal-termination exit is
normalized to failure instead of allowing AgentGuard to assume success.
Compatibility exit/status fields remain fallbacks, and standard error becomes
`stderr`. Edit and MCP post payloads retain the result output and metadata
without parsing human-readable text.

`workdir` is an OpenCode path argument, not shell text. Matching OpenCode
v1.18.11, the adapter does not strip quotes or expand `~`; those characters are
ordinary parts of a relative path unless OpenCode changes its own resolver.

## OpenCode Callback Model

OpenCode awaits direct hooks such as `chat.message`, `permission.ask`,
`shell.env`, and `tool.execute.before/after`, but dispatches the generic `event`
callback without awaiting it. The adapter handles them separately.

### Direct hooks

- `chat.message` owns exactly-once lazy session startup. It awaits the cached
  start promise, runs prompt-submit, then appends start, stop, and prompt
  context to `output.message.system`. `session.created` pre-registers the
  session record but cannot run startup because its event has no agent identity;
  deferring until `chat.message` is what permits internal-agent suppression.
- `tool.execute.before` starts the applicable pre-hook and stores returned
  context by OpenCode `callID`.
- `tool.execute.after` retrieves only that `callID`, runs the post-hook, appends
  clearly delimited guard context to `output.output`, and deletes the entry.
- `permission.ask` runs the notification hook best-effort.
- `shell.env` supplies generic OpenCode agent/session identity to Bash commands,
  allowing direct Hive Memory writes to coordinate with hook reminders.

Agent names `title`, `summary`, and `compaction` are internal maintenance
sessions and do not start AgentGuard lifecycle or memory hooks. Task subagents
retain their own session IDs and remain guarded.

### Claude and Codex parity

The OpenCode adapter covers the same configured shared integration categories:

| Category | OpenCode bridge |
| --- | --- |
| global rules and playbook routing | native `~/.config/opencode/AGENTS.md` generated target |
| gstack skills | native transformed tree with duplicate Claude skill fallback disabled |
| startup and finalization | `session.created`, first `chat.message`, `session.deleted`, `dispose` |
| prompts and response completion | `chat.message`, `session.idle` |
| host attention | `permission.ask` |
| Bash, edit/write/patch, MCP | `tool.execute.before/after` |
| direct Hive Memory writes | `shell.env` agent and session identity |
| task subagents | distinct non-maintenance session IDs |
| installation and health | ownership-aware `dot update` merge plus `dot doctor` |

Runtime-specific UI features that Claude or Codex may own outside the shared
AgentGuard configuration are not duplicated. The parity contract is the shared
AgentGuard/Hive integration configured in this dotfiles repository.

### Event callback

The callback synchronously appends work to a per-session promise chain before it
returns:

- `session.created` pre-registers the session record;
- `session.idle` queues Stop once per user-message generation;
- `session.deleted` queues SessionEnd once and removes state after it completes.

`dispose()` queues and awaits SessionEnd for every remaining active session, so
normal OpenCode shutdown finalizes sessions even when no delete event arrived.
Start and end are each at most once. Session records are finalized and evicted
only when deleted or disposed, so elapsed time or a large number of concurrent
sessions cannot manufacture a SessionEnd/SessionStart pair. Orphaned call
records alone are bounded by a TTL and maximum map size. Per-session
missing-hook notices disappear with their owning record.

This chain is the barrier between unawaited event dispatch and awaited direct
hooks: `chat.message` waits for prior lifecycle work for its session, while an
event handler never assumes OpenCode will await its returned promise.

## MCP Identification

The `config` callback retains OpenCode's shared config object so MCP entries
added by a later plugin remain visible. Before classifying any non-direct tool,
the adapter refreshes the authoritative connected-server inventory through the
local OpenCode client. This includes servers added at runtime and excludes
disabled or failed servers that cannot expose tools. If status is temporarily
unavailable, the last known inventory falls back to enabled shared-config
entries.

OpenCode exposes a connected MCP tool as
`sanitize(server) + "_" + sanitize(tool)`, where `sanitize` replaces characters
outside `[A-Za-z0-9_-]` with `_`.

The adapter compares every active server prefix:

- exactly one matching prefix identifies the server and tool;
- no match leaves an unrelated built-in tool untouched;
- multiple matches are ambiguous and fail closed before execution.

For `read_mcp_resource`, `list_mcp_resources`, and
`list_mcp_resource_templates`, an explicit `args.server` identifies the server.
When a list operation omits `server`, the pre-hook is invoked once for each
active server and any denial blocks the operation. The matching post-hook
uses the same captured server identities from that `callID`.

## Context and Concurrency

Pre-tool context is keyed by `callID`, never only by session. Concurrent tools
in one session cannot consume one another's context. Entries are removed after
the matching post-hook, on session finalization, or when their TTL expires.

Context appended to messages or tool results is delimited with a stable
AgentGuard heading. The adapter does not parse or replace OpenCode's original
display text.

## Validation

Installation tests must prove:

1. first-run install and automatic global plugin discovery;
2. unchanged rerun preserves bytes, inode, and modification time;
3. no duplicate or temporary file appears and unrelated plugins survive;
4. changed managed source updates atomically;
5. unmanaged regular files and symlinks at the target are preserved;
6. removing the source prunes only a marked managed target.

Adapter tests must prove:

1. exact environment, shell agent/session identity, effective Bash working
   directory, event names, and JSON translations, including normal and
   signal-termination exit metadata;
2. lazy start is exactly once and reaches the first prompt;
3. delayed unawaited lifecycle events serialize before later direct hooks;
4. duplicate idle events produce one Stop per message generation;
5. deletion and `dispose()` each finalize at most once;
6. exit 2 uses standard error and blocks before execution;
7. protected pre-hook launch or input failure, process-tree timeout, and
   malformed non-empty output fail closed, while a missing executable is
   advisory;
8. post/lifecycle failure is advisory;
9. `callID` keeps concurrent pre/post context isolated and cleans it up;
10. exact and ambiguous MCP prefix cases, later-plugin and runtime server
    additions, disabled-prefix overlap, and active resource-list fan-out;
11. internal maintenance agents are skipped and task subagents are retained;
12. the actual adapter module loads through the installed OpenCode
    global-plugin path;
13. active sessions survive clock advancement and session-record pressure
    without synthetic lifecycle transitions.
14. the real dotfiles `hm` launcher derives `opencode` plus the OpenCode session
    ID from the injected Bash environment.

The focused and final commands are:

- `dot-test core-merges opencode-agentguard core-doctor`;
- `dot-test core-static workflow-consistency`;
- the full `dot-test` suite;
- `checkrun format`;
- `checkrun lint`;
- `git diff --check`.

The final review must specifically inspect idempotence, unmanaged-file
preservation, session ordering, `callID` isolation, and fail-closed protected
pre-hook behavior.
