# ET Tunnel Test Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make ET tunnel tests deterministic, leak-free, and faster than 45 seconds on NAS.

**Architecture:** Keep production tunnel behavior unchanged while making test dependencies explicit. Extend the portable timeout supervisor so every suite-owned process group is contained, then shard ET coverage only if the repaired benchmark still exceeds the target.

**Tech Stack:** Bash, POSIX shell fixtures, Python 3 standard library, `dot test`, GitHub Actions.

## Global Constraints

- Preserve the production preference for `socat` over `ncat`.
- Do not shorten runtime safety deadlines to make tests faster.
- Keep relay fixture behavior in one authoritative helper.
- Preserve timeout, cancellation, and child exit status codes.
- `dot test et-tunnel` must continue to run all ET tunnel coverage.
- Complete ET coverage must finish within 45 seconds on NAS.

---

### Task 1: Isolate ET relay and local-port fixtures

**Files:**

- Modify: `.local/lib/dot/tests/et-tunnel-test`

**Interfaces:**

- Consumes: generated supervisor relay argv from `.local/bin/et-tunnel`.

- Produces: fake `socat` and `ncat` programs with the existing remote PID/FIFO/log contract.

- [ ] **Step 1: Verify the existing test fails for the intended reasons**

Run `./.local/bin/dot test -s et-tunnel` and confirm failures name missing
remote relay PID files and occupied custom-transport ports.

- [ ] **Step 2: Add a `socat` fixture that exercises the real preference branch**

Create a fake `socat` beside fake `ncat`. Normalize its listen, exec, receive,
and send argv into the existing data/control/send fixture actions. Assertions
must continue to observe real supervisor behavior through PID files, FIFOs, and
process lifecycle.

- [ ] **Step 3: Isolate illustrative VNC ports**

Set `ET_TUNNEL_TEST_LSOF_EXIT=1` only around the two custom-transport calls
that use ports 5901 and 5902. Leave production port detection and explicit
port-in-use tests unchanged.

- [ ] **Step 4: Run the focused ET test**

Run `./.local/bin/dot test -s et-tunnel`. Expected: all assertions pass.

- [ ] **Step 5: Commit**

Commit the host-independent fixture changes with their focused test evidence.

### Task 2: Contain descendants after normal suite exit

**Files:**

- Modify: `.local/lib/dot/tests/timeout.py`
- Modify: `.local/lib/dot/tests/core/runner.sh`

**Interfaces:**

- Consumes: the child session created by `subprocess.Popen(..., start_new_session=True)`.

- Produces: the suite leader's original status after all remaining process-group members are terminated.

- [ ] **Step 1: Write a failing runner regression**

Add a synthetic passing suite that starts `sleep 300` in the background,
records its PID, prints a valid results summary, and exits zero. Run it through
`dot test`, then assert the recorded PID has stopped.

- [ ] **Step 2: Run the runner shard and observe RED**

Run `DOT_CORE_SHARD=main DOT_CORE_SKIP_STATIC=1 ./.local/lib/dot/tests/core-test`.
Expected: the new descendant-cleanup assertion fails while existing runner
assertions pass.

- [ ] **Step 3: Clean the child process group after normal exit**

Refactor `timeout.py` process-group termination so cancellation, expiration,
and successful leader exit share the same bounded TERM/KILL cleanup. Preserve
the leader status returned from the normal path.

- [ ] **Step 4: Run the runner shard and timeout consumers**

Run the focused core shard and `./.local/bin/dot test nvim`. Expected: all
runner and portable-timeout assertions pass.

- [ ] **Step 5: Commit**

Commit the containment behavior and regression coverage.

### Task 3: Meet the ET runtime target

**Files:**

- Modify or move: `.local/lib/dot/tests/et-tunnel-test`
- Create if needed: `.local/lib/dot/tests/et-tunnel-fixture.sh`
- Create if needed: `.local/lib/dot/tests/et-tunnel-*-test`

**Interfaces:**

- Consumes: the repaired host-independent ET fixture from Task 1.

- Produces: parallel auto-discovered shards selected together by `dot test et-tunnel`.

- [ ] **Step 1: Benchmark repaired aggregate coverage**

Run `/usr/bin/env time -p ./.local/bin/dot test et-tunnel` and record elapsed
wall time. If it is at most 45 seconds, skip Steps 2-4.

- [ ] **Step 2: Split independent behavior groups**

Move shared setup into `et-tunnel-fixture.sh` and create focused executable
shards for default/remote supervisor, custom transport/job control, and
collision/validation behavior. Do not duplicate fixture policy.

- [ ] **Step 3: Verify aggregate selection and behavior**

Run `./.local/bin/dot test -l`, then `./.local/bin/dot test et-tunnel`.
Expected: every shard is selected and all assertions pass.

- [ ] **Step 4: Re-benchmark**

Run `/usr/bin/env time -p ./.local/bin/dot test et-tunnel`. Expected: elapsed
wall time is at most 45 seconds on NAS.

- [ ] **Step 5: Commit**

Commit the measured runtime improvement, or record in the Task 1 report that
sharding was unnecessary because the target was already met.

### Task 4: Verify, review, and land

**Files:**

- Review all files changed since `origin/main`.

**Interfaces:**

- Consumes: Tasks 1-3.

- Produces: a green pull request merged into `main`.

- [ ] **Step 1: Clean known leaked test processes**

Resolve the exact two `socat` PIDs whose argv references deleted dot test
temporary roots, terminate only those processes, and verify they stopped.

- [ ] **Step 2: Run local verification**

Run `checkrun format`, `checkrun lint`, `git diff --check`, focused ET and
runner tests, and full `./.local/bin/dot test`.

- [ ] **Step 3: Perform fresh-eyes and code review**

Review the complete diff for process-group safety, cross-platform behavior,
fixture fidelity, test isolation, and scope.

- [ ] **Step 4: Create and verify the pull request**

Use the repository PR template, push the explicit branch ref, create the PR,
and verify its head commit.

- [ ] **Step 5: Land when green**

Wait for required CI, squash-merge the PR, update the live `main`, verify clean
status, and remove the completed worktree and local feature branch.
