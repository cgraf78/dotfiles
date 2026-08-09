# Full Pull-Request Platform Matrix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run dotfiles pull-request and push CI on all eight platforms in the shared `full` shell matrix and require every platform check before merge.

**Architecture:** The caller selects the existing shared `full` matrix through the reusable workflow's public `matrix-set` input. A static dotfiles test guards that caller-owned selection, while GitHub branch protection continues to require the selector and each emitted platform job individually.

**Tech Stack:** GitHub Actions reusable workflows, Bash test helpers, GitHub branch-protection API

## Global Constraints

- Keep `cgraf78/actions` unchanged and retain the existing immutable workflow SHA.
- Use the shared `full` matrix as the only source of platform membership.
- Do not change dependency bootstrap or repository-secret behavior.
- Defer Android/Termux to a separate emulator-backed pull request.
- Land only after macOS, CentOS Stream, Arch, Debian, Ubuntu, WSL, Fedora, and Alpine all pass.

---

### Task 1: Require the shared full matrix

**Files:**

- Modify: `.local/lib/dot/tests/core/static.sh`

- Modify: `.github/workflows/test.yml`

**Interfaces:**

- Consumes: the reusable `shell-ci.yml` input `matrix-set`, whose accepted value `full` emits all eight shared platforms

- Produces: a workflow contract that explicitly selects `full`, guarded by the core static test suite

- [ ] **Step 1: Write the failing workflow-contract test**

Extend the existing non-comment workflow scan in
`.local/lib/dot/tests/core/static.sh` to track the `jobs`, `shell`, and `with`
nesting levels. Set `_ci_uses_full_matrix=1` only for this active input:

```bash
    elif ((_ci_in_shell_with)) && [[ "$_ci_code" =~ ^[[:space:]]{6}matrix-set:[[:space:]]+full[[:space:]]*$ ]]; then
      _ci_uses_full_matrix=1
```

Report the contract after the scan:

```bash
  if ((_ci_uses_full_matrix)); then
    _pass "CI workflow: requests full platform matrix"
  else
    _fail "CI workflow: requests full platform matrix"
  fi
```

- [ ] **Step 2: Run the focused test and verify the new assertion fails**

Run:

```bash
.local/bin/dot-test core
```

Expected: exit nonzero with
`FAIL: CI workflow: requests full platform matrix`.

Also comment out the setting as `# matrix-set: full` and rerun the focused
test. It must still fail, proving comments cannot satisfy the contract.

- [ ] **Step 3: Select the full matrix in the caller**

Add the input alongside the existing `setup` and `test-command` inputs in
`.github/workflows/test.yml`:

```yaml
    with:
      matrix-set: full
      setup: dotfiles
      test-command: .local/bin/dot-test
```

- [ ] **Step 4: Run focused verification**

Run:

```bash
.local/bin/dot-test core
actionlint .github/workflows/test.yml
```

Expected: both commands exit zero, and the core suite reports
`PASS: CI workflow: requests full platform matrix`.

- [ ] **Step 5: Run repository verification**

Run:

```bash
checkrun format
checkrun lint
.local/bin/dot-test
git diff --check
```

Expected: every command exits zero.

- [ ] **Step 6: Commit the implementation**

Stage only `.github/workflows/test.yml`,
`.local/lib/dot/tests/core/static.sh`, and this plan. Commit with:

```text
Test the full platform matrix in CI

Summary

Make pull-request and push validation use every platform already owned by
the shared shell CI workflow.

- select the shared `full` matrix explicitly
- guard the caller contract with a static test

Testing

- `checkrun format`
- `checkrun lint`
- `.local/bin/dot-test`
- `actionlint .github/workflows/test.yml`
```

### Task 2: Publish, gate, and land

**Files:**

- No repository file changes

- Update: GitHub `main` branch required status checks

**Interfaces:**

- Consumes: check contexts emitted by the pull request at its current head SHA

- Produces: branch protection requiring the selector plus all eight platform checks

- [ ] **Step 1: Review the final branch**

Read `~/.config/agent-rules/playbooks.d/review/fresh-eyes.md`, review the complete
`origin/main..HEAD` diff for correctness, platform compatibility, stale
references, scope, and public-data safety, then resolve every actionable
finding.

- [ ] **Step 2: Push the explicit branch destination and create the PR**

Push:

```bash
git push origin HEAD:refs/heads/ci/full-platform-matrix
```

Verify the remote branch resolves to local `HEAD`, locate and follow the
repository PR template if one exists, and create a squash-ready PR whose
summary explains that dotfiles now selects the shared `full` matrix.

- [ ] **Step 3: Wait for all eight platform checks**

Watch the PR until these contexts all conclude successfully:

```text
shell / Platforms / select-platforms
shell / Platforms / macOS
shell / Platforms / CentOS Stream
shell / Platforms / Arch
shell / Platforms / Debian
shell / Platforms / Ubuntu
shell / Platforms / WSL
shell / Platforms / Fedora
shell / Platforms / Alpine
```

- [ ] **Step 4: Extend branch protection**

Preserve every existing branch-protection setting and required check, then add:

```text
shell / Platforms / WSL
shell / Platforms / Fedora
shell / Platforms / Alpine
```

Use GitHub Actions app ID `15368`, matching the existing required platform
checks.

- [ ] **Step 5: Verify the gate and merge**

Read branch protection back and verify it requires exactly the selector plus
all eight platform contexts. Re-read PR status, confirm the head SHA matches
the pushed commit and every required check is green, then squash-merge without
coupling the remote merge to local branch deletion.

- [ ] **Step 6: Synchronize and clean up**

Fetch `origin/main`, update the primary dotfiles checkout to the merged commit,
confirm it is clean, remove this linked worktree, prune worktree metadata, and
delete the completed local feature branch after confirming the PR is merged.
