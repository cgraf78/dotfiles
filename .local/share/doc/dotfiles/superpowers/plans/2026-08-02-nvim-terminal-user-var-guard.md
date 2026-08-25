# Neovim Terminal User-Variable Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop `DOT_TMUX` WezTerm user-variable publication inside embedded Neovim terminals.

**Architecture:** The dotfiles shell integration delegates eligibility to Termnav's existing context predicate. Its focused runtime test extends the current publisher probe, keeping the behavior and test ownership local to the WezTerm integration.

**Tech Stack:** Bash/Zsh sourceable shell integration, Termnav API stub, dotfiles `dot test` runner.

## Global Constraints

- Preserve one-time source-time publication; add no prompt-time work.
- Preserve publication for ordinary tmux shells outside Neovim.
- Do not make an unavailable Termnav helper a shell-startup failure.

---

### Task 1: Guard the shell publisher and cover the embedded-terminal context

**Files:**

- Modify: `.config/shell/interactive.d/53-wezterm.sh`
- Modify: `.local/lib/dot/tests/wezterm-test`

**Interfaces:**

- Consumes: optional `_termnav_wezterm_active()` predicate and existing `_termnav_wezterm_set_user_var(name, value)` helper.

- Produces: zero publisher calls when `NVIM` is non-empty; existing `DOT_TMUX=true` call for a tmux shell outside Neovim.

- [ ] **Step 1: Write the failing test**

Extend `_tmux_context_probe` to receive and export an `NVIM` value, then add a Bash and Zsh assertion whose expected publication log is empty when `TMUX` and `NVIM` are both non-empty.

- [ ] **Step 2: Run test to verify it fails**

Run: `./.local/bin/dot test -s wezterm`

Expected: the new embedded-Neovim assertions fail because the current publisher calls `_termnav_wezterm_set_user_var` unconditionally.

- [ ] **Step 3: Write minimal implementation**

Make `_dot_wezterm_publish_tmux_context` return before publishing unless `_termnav_wezterm_active` exists and returns success. Keep its `TMUX` value mapping unchanged after that guard.

- [ ] **Step 4: Run test to verify it passes**

Run: `./.local/bin/dot test -s wezterm`

Expected: all publisher and existing WezTerm integration checks pass for Bash and Zsh.

- [ ] **Step 5: Commit**

Stage the shell integration, focused test, design, and plan documents. Commit using the repository's imperative title and `Summary`/`Testing` body format.
