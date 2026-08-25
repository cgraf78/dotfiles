# `dot update` Exit Status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve best-effort convergence while returning nonzero when a
required `dot update` stage fails.

**Architecture:** Required stages return ordinary shell status. The update
orchestrator accumulates those statuses, continues through later safe stages,
renders one completion message, and returns the aggregate result to the
launcher.

**Tech Stack:** Bash, the existing dot core test harness, Shdeps JSONL update
status.

## Global Constraints

- Keep cron dirty-worktree skips and cron lock contention successful.
- Keep Shdeps warning-only updates successful.
- Stop immediately when initial Shdeps bootstrap fails because overlay filters
  are unavailable.
- Always run safe later stages after recoverable failures.
- Add no successful-path external commands.
- Do not affect shell or Neovim startup.

---

### Task 1: Specify merge and completion status

**Files:**

- Modify: `.local/lib/dot/tests/core/merges.sh`
- Modify: `.local/lib/dot/tests/core/main.sh`

**Interfaces:**

- Consumes: `_run_merges` and `_ui_done`.

- Produces: tests for merge failure status and error-aware completion text.

- [ ] **Step 1: Write a failing merge-status test**

Capture `_run_merges` without `|| true` after installing a failing hook. Assert
that surviving hooks still ran and the function returned `1`.

- [ ] **Step 2: Write failing completion-message tests**

Call `_ui_done 0` and `_ui_done 1`. Assert the zero case contains `Done in`
and the failure case contains `Done with errors in`.

- [ ] **Step 3: Verify RED**

Run:

```bash
DOT_TEST_NO_COLOR=1 .local/bin/dot test core
```

Expected: `_run_merges` still returns zero and `_ui_done 1` still prints the
success message.

### Task 2: Specify best-effort orchestration and launcher status

**Files:**

- Modify: `.local/lib/dot/tests/core/commands.sh`

**Interfaces:**

- Consumes: `_dot_update_finalize`, `_dot_update`, and the public `dot`
  launcher.

- Produces: regression tests for continued convergence and final status.

- [ ] **Step 1: Write a failing recoverable-stage test**

In a subshell, replace `_run_shdeps_update_ui` with a fixture that returns `1`,
replace `_run_merges` and `_normalize_filtered` with marker-writing fixtures,
and call `_dot_update_finalize`. Assert both markers exist and the return
status is `1`.

- [ ] **Step 2: Write a failing repository-stage continuation test**

In a subshell, make `_dot_update_sync_repos` return `1` and make
`_dot_update_finalize` write a marker and return `0`. Call `_dot_update
--skip-pull`; assert the marker exists and the final status is `1`.

- [ ] **Step 3: Write a failing public-launcher test**

Add a failing merge hook to the existing update fixture, invoke
`dot update --skip-pull`, and assert:

```text
status=1
Configs    warning
Cleanup    ok
Done with errors in
```

Remove the fixture hook after the assertion.

- [ ] **Step 4: Verify RED**

Run:

```bash
DOT_TEST_NO_COLOR=1 .local/bin/dot test core
```

Expected: update completes but the captured status remains zero.

### Task 3: Implement aggregate failure propagation

**Files:**

- Modify: `.local/lib/dot/core/merges.sh`
- Modify: `.local/lib/dot/core/progress-ui.sh`
- Modify: `.local/lib/dot/core/update.sh`
- Modify: `.local/bin/dot`

**Interfaces:**

- Consumes: required-stage shell statuses.

- Produces: `_run_merges -> 0|1`, `_ui_done [status]`,
  `_dot_update_finalize -> 0|1`, and `_dot_update -> 0|1`.

- [ ] **Step 1: Return merge-hook failure**

After rendering the Configs stage, return whether
`DOT_MERGE_FAILED_COUNT` is zero.

- [ ] **Step 2: Render the aggregate result**

Accept an optional status argument in `_ui_done`; use `Done with errors in`
when it is nonzero and retain the existing success text and reload hint.

- [ ] **Step 3: Accumulate finalization failures**

In `_dot_update_finalize`, record failures from `_link_overlays`,
`_run_shdeps_update_ui`, and `_run_merges`. Always run cleanup, call
`_ui_done "$status"`, and return the aggregate status. Keep warning-only Shdeps
results at zero.

- [ ] **Step 4: Continue after repository failure**

In `_dot_update`, record `_dot_update_sync_repos` failure, always call
`_dot_update_finalize`, and return nonzero if either failed. Preserve the
existing early successful cron dirty-worktree exit.

- [ ] **Step 5: Preserve the public status**

Replace the launcher's unconditional `exit 0` after `_dot_update` with an
explicit capture and `exit "$status"`. Keep the initial Shdeps bootstrap before
overlay discovery so a bootstrap failure remains fail-fast.

- [ ] **Step 6: Verify GREEN**

Run:

```bash
DOT_TEST_NO_COLOR=1 .local/bin/dot test core
git diff --check
```

Expected: all checks pass.

### Task 4: Document, verify, and commit the status contract

**Files:**

- Modify: `.local/share/doc/dot/dot.md`
- Verify all files changed on this branch.

**Interfaces:**

- Consumes: Tasks 1 through 3.

- Produces: documented command behavior and one reviewable implementation
  commit after the design commit.

- [ ] **Step 1: Document exit semantics**

State that update remains best effort but returns nonzero after required-stage
failures, and list the advisory zero-status cases.

- [ ] **Step 2: Run repository gates**

Run:

```bash
checkrun format
checkrun lint
DOT_TEST_NO_COLOR=1 .local/bin/dot test
git diff --check
```

- [ ] **Step 3: Review the complete branch diff**

Confirm no `set -e` behavior accidentally prevents later stages, warning-only
paths remain zero, and no debug instrumentation or unrelated changes remain.

- [ ] **Step 4: Commit**

Commit the implementation with the repository's required `Summary` and
`Testing` sections.
