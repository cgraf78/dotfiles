# OpenCode AgentGuard Hooks Implementation Plan

> **Superseded (2026-08-07):** This plan describes the completed, original
> dotfiles-owned adapter. The adapter and its behavioral suite have since moved
> to `share/agentguard/integrations/opencode/` in AgentGuard. Dotfiles now owns
> only provider resolution and safe installation; file paths and tasks below are
> retained as historical implementation evidence, not current instructions.
>
> Historical execution note: the original implementation used a task-by-task
> agent workflow. It is complete; do not execute this plan against the current
> dotfiles layout.

**Goal:** Install an idempotent, source-managed OpenCode plugin that translates
OpenCode callbacks into the existing AgentGuard hook protocol.

**Architecture:** A narrow Bash merge hook owns one marked generated plugin
file without touching OpenCode JSON configuration. The JavaScript plugin keeps
runtime translation, lifecycle serialization, per-call context, and
fail-closed pre-tool behavior inside OpenCode's supported global plugin API.

**Tech Stack:** Bash, JavaScript ES modules, Node/Bun built-ins, OpenCode plugin
API, AgentGuard hook protocol, dotfiles test harness.

## Global Constraints

- Work only in the isolated feature worktree selected for this branch.
- Do not edit generated runtime targets in the live home.
- Preserve an unmanaged target file or symlink.
- An unchanged merge must preserve bytes, inode, and modification time and
  create no temporary sibling.
- Missing AgentGuard executables are advisory; failures after a protected
  pre-hook is found fail closed.
- Use the exact translations and timeout matrix in the approved design spec.
- Do not modify `opencode.jsonc`.

---

### Task 1: Idempotent managed plugin installation

**Files:**

- Create: `.config/dot/merge-hooks.d/opencode/agentguard.js`
- Create: `.config/dot/merge-hooks.d/opencode/README.md`
- Create: `.local/lib/dot/core/merge-hooks/opencode.sh`
- Modify: `.local/lib/dot/tests/core/merges.sh`
- Modify: `.github/shellcheck-files.txt`

**Interfaces:**

- Consumes: `_merge_hook_tmp_for`, `_merge_hook_commit_tmp`, `_warn`, and
  `HOME` from dot core.

- Produces: `merge()` installing
  `$HOME/.config/opencode/plugins/dotfiles-agentguard.js`, with
  `DOT_OPENCODE_SOURCE_DIR` as a test override.

- [ ] **Step 1: Add failing merge tests**

Add one focused section to `dot_core_test_merges()` that sources
`opencode.sh` against a fixture home and asserts:

```bash
target="$opencode_home/.config/opencode/plugins/dotfiles-agentguard.js"
test -f "$target"
cmp -s "$opencode_source/agentguard.js" "$target"
```

Capture `stat` inode and mtime plus a directory listing, run the hook again,
and assert all are unchanged. Add dedicated cases for source updates, preserved
unrelated plugins, preserved unmanaged target files, preserved target
symlinks, marked-target pruning, and no temporary siblings.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
./.local/bin/dot test core-merges
```

Expected: the OpenCode section fails because `opencode.sh` and its source do
not exist.

- [ ] **Step 3: Implement the minimal ownership-aware installer**

Create a Bash hook with:

```bash
_dot_opencode_source_dir="${DOT_OPENCODE_SOURCE_DIR:-$_dot_opencode_hook_dir/../../../../../.config/dot/merge-hooks.d/opencode}"
_dot_opencode_marker='// dot-managed:opencode-agentguard-plugin'

merge() {
  local src="$_dot_opencode_source_dir/agentguard.js"
  local dst="$HOME/.config/opencode/plugins/dotfiles-agentguard.js"
  # Install/update only a marked regular non-symlink target.
  # Return before temp creation when cmp reports identical bytes.
  # Prune only a marked regular non-symlink target when src is absent.
}
```

Use `_merge_hook_tmp_for` and `_merge_hook_commit_tmp` for changed writes. Add
the hook to `.github/shellcheck-files.txt` and document ownership, restart
semantics, and the generated path.

- [ ] **Step 4: Run focused tests and static checks**

Run:

```bash
./.local/bin/dot test core-merges core-static
```

Expected: both suites pass with zero failures.

- [ ] **Step 5: Commit the installation slice**

Commit only this task's files with a message following the repository's
`Summary` and `Testing` format.

---

### Task 2: Adapter hook runner and exact payload translation

**Files:**

- Modify: `.config/dot/merge-hooks.d/opencode/agentguard.js`
- Create: `.local/lib/dot/tests/opencode-agentguard-test`
- Modify: `.github/shellcheck-files.txt`

**Interfaces:**

- Consumes: OpenCode plugin factory input `{ directory, client }` and direct
  hook callback arguments.

- Produces: the sole module export `AgentGuardPlugin`; internal helpers
  `runHook`, `toolTargets`, `prePayload`, and `postPayload` remain unexported so
  OpenCode does not mistake them for plugin factories.

- [ ] **Step 1: Add a failing Node fixture suite**

Create an executable Bash test runner that skips with:

```bash
echo "SKIP: opencode-agentguard-test (node unavailable)"
```

when Node is absent. Otherwise, build executable fixture
`agent-hook-*` scripts that append stdin plus selected environment variables to
a JSON-lines log. Import the plugin with a cache-busting URL and invoke its
callbacks. Assert exact payloads for:

```text
bash -> Bash/command
edit -> Edit/file_path,old_string,new_string,replace_all
write -> Write/file_path,content
apply_patch -> Edit/patch
configured MCP -> mcp__server__tool/original arguments
```

Also assert `cwd`, `AGENTGUARD_NAME=opencode`,
`AGENTGUARD_SESSION_ID`, event names, Bash post `stdout`, and the documented
timeout override. Exercise `shell.env` through the real dotfiles `hm` launcher
and assert that direct commands derive the `opencode` agent plus session ID
without replacing unrelated environment entries.

- [ ] **Step 2: Run the adapter test and verify RED**

Run:

```bash
./.local/bin/dot test opencode-agentguard
```

Expected: failure because the source file does not yet export a working plugin.

- [ ] **Step 3: Implement spawning and translation**

Implement the source plugin with only:

```js
export const AgentGuardPlugin = async ({ directory, client }) => {
  return {
    config: async (config) => {},
    "shell.env": async (input, output) => {},
    "chat.message": async (input, output) => {},
    "permission.ask": async (input) => {},
    "tool.execute.before": async (input, output) => {},
    "tool.execute.after": async (input, output) => {},
    event: async ({ event }) => {},
    dispose: async () => {},
  }
}
```

The internal runner resolves `$HOME/.local/bin/<hook>` before `PATH`, spawns
the fixed Bash bootstrap with `BASH_ENV`, writes one JSON document, captures
both streams, enforces the timeout matrix, and returns parsed context plus exit
status. Whitespace output is empty; non-empty output must parse as JSON.

Implement exact snake-case tool translation from the spec. MCP matching must
require exactly one sanitized active-server prefix; ambiguous matches throw
before tool execution. Retain the shared config object, refresh runtime server
status through the local client, exclude disabled servers, and preserve the
last known inventory through transient status failures. Resource list
operations without `args.server` fan out over active servers.

- [ ] **Step 4: Prove failure semantics**

Extend the fixture suite with distinct tests for exit 2 stderr denial, launch
error, early stdin closure, timeout, malformed successful pre output, missing
executable, post-hook failure, and malformed post output. Verify protected
failures throw, missing executables do not, and post failures only log.

- [ ] **Step 5: Run the adapter suite**

Run:

```bash
./.local/bin/dot test opencode-agentguard
```

Expected: suite summary reports zero failures.

- [ ] **Step 6: Commit the protocol slice**

Commit the plugin, test runner, and shellcheck inventory update with the
required message format.

---

### Task 3: Lifecycle ordering, context isolation, and bounded state

**Files:**

- Modify: `.config/dot/merge-hooks.d/opencode/agentguard.js`
- Modify: `.local/lib/dot/tests/opencode-agentguard-test`

**Interfaces:**

- Consumes: OpenCode direct hooks and unawaited event bus events.

- Produces: per-session `start`, `chain`, `generation`, `stoppedGeneration`,
  `ended`, and queued context state; per-`callID` tool context.

- [ ] **Step 1: Add failing lifecycle race tests**

Use delayed fixture hooks to assert:

- `session.created` and first `chat.message` invoke SessionStart exactly once;
- the first prompt waits for start context;
- two idle events in one generation invoke Stop once;
- another message permits one new Stop;
- `session.deleted` followed by `dispose()` invokes SessionEnd once;
- `dispose()` alone finalizes an active session;
- `title`, `summary`, and `compaction` agents create no lifecycle calls;
- a task subagent keeps its own session ID;
- two concurrent tool calls consume only their own `callID` context;
- clock advancement and a full session map do not finalize active sessions.

Invoke `event()` without awaiting its returned promise before the next direct
hook to reproduce OpenCode's real dispatch behavior.

- [ ] **Step 2: Run the lifecycle subset and verify RED**

Run:

```bash
./.local/bin/dot test opencode-agentguard
```

Expected: the new ordering, deduplication, or isolation assertions fail.

- [ ] **Step 3: Implement the state machine**

Create session records synchronously. Cache the session-start promise from the
first non-internal `chat.message` and append event work synchronously to each
record's promise chain. Make `chat.message` await both the chain and start
promise. Increment `generation` only for non-internal user messages. Queue Stop
only when `stoppedGeneration` differs. Queue SessionEnd at most once and delete
state only after completion.

Key pre-tool context by `callID`. Delete it after post-tool, finalization, or
TTL expiry. Enforce the documented TTL and map cap for orphaned calls only;
retain active session records until delete or dispose. Keep missing-hook notices
inside their owning session records. Append context under a stable delimiter
without parsing original display text.

- [ ] **Step 4: Run adapter and merge suites**

Run:

```bash
./.local/bin/dot test opencode-agentguard core-merges
```

Expected: both suites pass with zero failures.

- [ ] **Step 5: Commit the lifecycle slice**

Commit the plugin and tests with the repository message format.

---

### Task 4: Doctor and operator documentation

**Files:**

- Modify: `.local/lib/dot/core/doctor/agent-hooks.sh`
- Modify: `.local/lib/dot/tests/core/doctor.sh`
- Modify: `.config/dot/merge-hooks.d/README.md`
- Modify: `.config/dot/merge-hooks.d/agent-rules/targets.d/80-targets.replace/50-native.txt`
- Modify: `.config/shell/env.d/60-tools.sh`
- Modify: `.local/lib/dot/gstack-register/README.md`
- Modify: `.local/lib/dot/tests/agent-rules-test`
- Modify: `.local/lib/dot/tests/core/static.sh`

**Interfaces:**

- Consumes: `command -v opencode` and the installed managed plugin path.

- Produces: one doctor OK result for a marked regular installed plugin, or a
  warning for a missing, symlinked, or unmarked target.

- [ ] **Step 1: Add failing doctor assertions**

Extend doctor fixtures so an available `opencode` command with a marked regular
plugin reports:

```text
OpenCode AgentGuard plugin installed
```

Add separate cases where the plugin is absent or unmarked and assert the doctor
warns without making the overall agent-hook section fatal.

- [ ] **Step 2: Run doctor tests and verify RED**

Run:

```bash
./.local/bin/dot test core-doctor
```

Expected: new OpenCode doctor assertions fail.

- [ ] **Step 3: Implement the doctor check and docs**

Add a helper that checks the target only when `opencode` is on `PATH`, verifies
regular non-symlink ownership, and emits OK or warning. Add the OpenCode source
and output to the merge-hook Configs table and explain that this thin
dotfiles-owned adapter reuses AgentGuard while OpenCode lacks a declarative hook
schema. Add `~/.config/opencode/AGENTS.md` to the native global-rule targets so
OpenCode does not depend on its optional Claude-compatibility fallback, and
verify that the generator writes and prunes that target like the existing
Claude and Codex targets. Disable only OpenCode's Claude skill fallback because
dotfiles already installs a transformed native gstack tree; leaving both
enabled advertises the same workflows under two name sets. Preserve CLAUDE.md
rule fallback for projects without AGENTS.md and preserve an explicit user
override of the environment default.

- [ ] **Step 4: Run focused verification**

Run:

```bash
./.local/bin/dot test agent-rules core-doctor core-static workflow-consistency
```

Expected: all suites pass with zero failures.

- [ ] **Step 5: Commit the doctor and docs slice**

Commit only the doctor and documentation changes with the required message
format.

---

### Task 5: Full verification, fresh-eyes review, and PR

**Files:**

- Modify only files required to resolve verified review findings.

**Interfaces:**

- Consumes: the complete branch diff against current `origin/main`.

- Produces: a verified pushed branch and an open GitHub pull request.

- [ ] **Step 1: Format and lint**

Run:

```bash
checkrun format
checkrun lint
git diff --check
```

Expected: every command exits zero.

- [ ] **Step 2: Run focused and full tests**

Run:

```bash
./.local/bin/dot test core-merges opencode-agentguard core-doctor core-static workflow-consistency
./.local/bin/dot test
```

Expected: every selected and discovered suite passes or reports an intentional
platform skip, with zero failures and no incomplete suites.

- [ ] **Step 3: Run both requested reviewers**

Give the complete `origin/main...HEAD` diff and the design spec to:

- GPT-5.6-sol at high reasoning;
- Claude Opus 5 at high reasoning.

Require findings to include severity, exact file/line evidence, and a concrete
failure mode. Verify each finding against source before changing code. Repeat
tests and both reviews after any substantive correction until both return no
actionable findings.

- [ ] **Step 4: Rebase and re-verify if main moved**

Fetch `origin`, compare the branch base with `origin/main`, and rebase only if
needed. Repeat all commands from Steps 1 and 2 after a rebase.

- [ ] **Step 5: Push explicitly and verify**

Run:

```bash
git push origin HEAD:refs/heads/feat/opencode-agentguard-hooks
git ls-remote --heads origin feat/opencode-agentguard-hooks
```

Expected: the remote branch resolves to local `HEAD`.

- [ ] **Step 6: Create and verify the PR**

Search `.github/` for pull request templates, use the template when present,
and create the PR with `gh`. Re-query it to verify the PR remains open and its
head SHA matches local `HEAD`. Stop at the open PR; do not merge it.
