# Android Developer Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route Watchexec through Termux packages, disable unsupported Trippy
installs on Android, and make Termux CI exercise the real `dot update` path.

**Architecture:** Keep platform policy in the Shdeps registry. Run the existing
Android smoke after a checkout-isolated `dot update --skip-pull`, then assert
the package-managed executable runs.

**Tech Stack:** Bash, Shdeps declarative configuration, GitHub Actions,
Termux `pkg`.

## Global Constraints

- Keep `.config/shdeps/10-deps.conf` columns aligned.
- Do not install Watchexec directly in the Android smoke script.
- Do not install Trippy on Android.
- Do not add work to shell or Neovim startup.
- Keep failure aggregation owned by `dot update`; require the CI caller to
  honor its public exit-status contract.

---

### Task 1: Specify Android routing and CI behavior

**Files:**

- Modify: `.local/lib/dot/tests/shdeps-hooks-test`
- Modify: `.local/lib/dot/tests/core/static.sh`

**Interfaces:**

- Consumes: Shdeps dependency rows and `.github/workflows/test.yml`.

- Produces: regression assertions for Android package routing and the Termux
  bootstrap command.

- [ ] **Step 1: Write failing Shdeps policy assertions**

Replace the macOS-only Watchexec assertion with explicit checks that its
package row includes `os:macos,os:android`, while Trippy remains macOS-only.
Require both GitHub rows to include `os:!macos,os:!android`.

- [ ] **Step 2: Write failing workflow assertions**

Extend the static workflow test to require the Termux command to run
`dot update --skip-pull` before `android-ci-smoke`, propagate a failed update
with `set -euo pipefail`, and require `termux-profiles: base,neovim`.

- [ ] **Step 3: Verify RED**

Run:

```bash
DOT_TEST_NO_COLOR=1 .local/bin/dot-test shdeps-hooks
DOT_TEST_NO_COLOR=1 .local/bin/dot-test core
```

Expected: failures report the missing Android Watchexec route, missing Android
exclusions, and missing real bootstrap command.

### Task 2: Implement the registry and Termux bootstrap path

**Files:**

- Modify: `.config/shdeps/10-deps.conf`
- Modify: `.github/workflows/test.yml`
- Modify: `.local/lib/dot/tests/android-ci-smoke`

**Interfaces:**

- Consumes: the existing `pkg`/`github` Shdeps row format and shared Termux
  workflow profiles.

- Produces: a package-managed `watchexec` command on Android and no Android
  Trippy route.

- [ ] **Step 1: Change dependency routing**

Keep the aligned table and set:

```text
watchexec                                  pkg              -             -                                              os:macos,os:android
fujiapple852/trippy                        github           trip          -                                              os:!macos,os:!android
watchexec/watchexec                        github           watchexec     -                                              os:!macos,os:!android
```

Leave the Trippy package row macOS-only.

- [ ] **Step 2: Run the real update in Termux**

Change the Termux command to run the checkout with an isolated `HOME`:

```yaml
termux-command: |-
  set -euo pipefail
  HOME="$PWD" PATH="$PWD/.local/bin:$PATH" .local/bin/dot update --skip-pull
  HOME="$PWD" PATH="$PWD/.local/bin:$PATH" bash .local/lib/dot/tests/android-ci-smoke
termux-profiles: base,neovim
```

- [ ] **Step 3: Make the smoke validate installed artifacts**

Remove the direct `pkg install -y neovim`. Retain the Neovim executable checks,
add Android routing assertions, and require:

```bash
command -v watchexec >/dev/null || fail "dot update did not install Watchexec"
watchexec --version >/dev/null 2>&1 ||
  fail "Termux Watchexec binary does not run"
```

- [ ] **Step 4: Verify GREEN**

Run:

```bash
DOT_TEST_NO_COLOR=1 .local/bin/dot-test shdeps-hooks
DOT_TEST_NO_COLOR=1 .local/bin/dot-test core
bash -n .local/lib/dot/tests/android-ci-smoke
git diff --check
```

Expected: all checks pass.

### Task 3: Verify and commit the Android change

**Files:**

- Verify all files changed on this branch.

**Interfaces:**

- Consumes: Tasks 1 and 2.

- Produces: one reviewable Android dependency/CI commit after the design
  commit.

- [ ] **Step 1: Run repository gates**

Run:

```bash
checkrun format
checkrun lint
DOT_TEST_NO_COLOR=1 .local/bin/dot-test
git diff --check
```

- [ ] **Step 2: Review the complete branch diff**

Confirm no direct Watchexec install exists in the smoke script, no Android
Trippy route remains, and no unrelated files changed.

- [ ] **Step 3: Commit**

Commit the implementation with the repository's required `Summary` and
`Testing` sections.
