# Working Tab Spinner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a roughly 150 ms Braille working spinner in tmux and WezTerm tabs while preserving existing attention behavior.

**Architecture:** One server-owned tmux helper sets a shared frame option every 150 ms while any pane is busy, publishes the existing client snapshot once on busy entry and every five seconds while busy, and sleeps between checks when idle. WezTerm uses a single 150 ms timer per GUI window only while its snapshots report work; it retains the normal one-second reconciliation and performs periodic reconciliation in that active timer. Both renderers read one shared UTF-8 frame file.

**Tech Stack:** tmux formats, Bash 3.2, WezTerm Lua, existing dotfiles tests.

**Spec:** `docs/superpowers/specs/2026-10-30-working-tab-spinner-design.md`

## Global Constraints

- Keep tmux `status-interval` at five seconds and `TERM_PANE_STATE` version 1.
- Render `●`/`!` alongside work, preserve focus and nested-child predicates, and never alter the pane border title.
- Use only the private tmux test socket; do not restart a live tmux or WezTerm session.
- The tmux helper is one process per live server, with reload takeover and bounded exit after server loss; no persistent state files.
- Leave WezTerm `status_update_interval` at its default 1000 ms; the busy-only timer must not multiply idle scans.
- A trapped tmux helper exit restores static `⋯` only if it still owns the server option. An untrappable kill may freeze the last frame while work remains, but cannot fabricate work after the busy predicate clears.
- The five-client/five-busy-window benchmark must add no more than 0.15 CPU core over idle and no more than one collector run per client per second after startup.
- A frame file missing or invalid at runtime falls back to static `⋯`.

## Review Focus

- Busy work in a background window must animate even when the selected pane is a shell (Task 1 test).
- An idle window with stale `@term_busy` on a shell pane must not start a helper (Task 1 test).
- A cleared busy mark must hide the glyph immediately and stop fast frame updates within a bounded deadline (Task 1 test).
- A snapshot that expires or a pane that vanishes must stop WezTerm animation without resurrecting stale work (Task 2 test).
- Narrow tabs must still reserve room for pending or failed attention beside the spinner (Task 2 test).
- Reload or another client attach must leave exactly one tmux frame updater (Task 1 test).
- A trapped helper exit must restore static `⋯`; an older helper must not overwrite a new owner's frame (Task 1 test).
- A WezTerm config reload must invalidate a callback queued by the old module instance (Task 2 test).

---

### Task 1: tmux streaming spinner

**Files:** Create `.config/terminal/working-spinner.frames`, `.local/bin/term-tab-spinner`; modify `.config/tmux/conf.d/10-base.conf`, `.config/tmux/README.md`, `.local/lib/dotfiles/tests/tmux-test`; add a focused private-PTY test if the existing suite cannot observe stream frames and process exit.

**Interfaces:** `term-tab-spinner --socket ABSOLUTE_SOCKET` runs one server-owned loop. It sets `@term_tab_spinner_owner` to a unique invocation token and writes `@term_tab_spinner_frame` at 150 ms only through a tmux `if-shell -F` command that compares ownership in the same server queue. A `list-panes -a` query finds any `@pane_display_busy`. The helper checks ownership and work at least once per second, sleeps while idle, exits on server loss or takeover, and restores `⋯` on trapped exit only if still owner. While busy, it keeps the existing per-client `term-pane-state` snapshot lease alive because frame writes defer status jobs. `@window_marker` reads the current frame only for busy windows.

- [ ] Write private-socket tests for idle, active, background, attention coexistence, missing frame file fallback, atomic reload takeover, trapped exit, and server shutdown; verify the new cases fail on the current config.
- [ ] Add the shared frame file and Bash 3.2 helper with argument validation, server owner token, one-second idle/work check, and 150 ms frame updates only while busy.
- [ ] Replace only the static work glyph in `@window_marker` with the shared frame option; start/restart the helper on config load and client attach, retaining current predicates and five-second interval.
- [ ] Run the focused tmux suite, ShellCheck, and a five-client/five-window attached-PTY frame/cost probe; verify one helper survives reload and none survive server shutdown. Check tmux 3.2a format parsing and macOS Bash 3.2 with fractional sleep before merge.
- [ ] Update the tmux README and commit this independently testable piece.

### Task 2: WezTerm local spinner

**Files:** Modify `.config/wezterm/attention.lua`, `.config/wezterm/wezterm.lua`, `.config/wezterm/README.md`, `.local/lib/dotfiles/tests/wezterm-test`.

**Interfaces:** `attention.setup_frames(PATH)` loads the shared file once from a path provided by `wezterm.lua` using `wezterm.config_dir`. `attention.format()` selects a frame from `wezterm.time.now():format('%s%3f')`, without needing a GUI-window ID. `attention.update()` claims a per-window `wezterm.GLOBAL` token in the active GUI status callback and starts one `wezterm.time.call_after(0.15, ...)` loop per GUI window only while fresh snapshots report work and frames are available. Each callback validates its window and token, redraws through the existing invisible right-status toggle, and reconciles snapshots plus stale-pane cleanup about once per second. No subprocess runs in the formatter.

- [ ] Add deterministic fake-timer Lua tests for frame progression, idle stability, missing/invalid frame file, duplicate prevention, config reload, expiry, vanished panes, one-cell width, narrow tabs, and pending/failed coexistence; verify they fail before implementation.
- [ ] Read and validate the shared frames once, implement per-window busy-only animation and periodic reconciliation, and leave the one-second status interval alone.
- [ ] Run the focused WezTerm suite and config validation; update the README and commit.

### Task 3: Integrated verification and rollout

**Files:** No new source files; fix only failures found by review or verification.

- [ ] Run `dot test`, relevant local CI checks, `git diff --check`, and an independent final review of lifecycle, performance, and unrelated side effects.
- [ ] Benchmark an isolated five-client/five-busy-window setup and compare collector invocations plus CPU to idle; adjust before rollout if overhead or tab motion is unacceptable.
- [ ] Open a PR, watch exact-head checks to green, land it, and verify landed main.
- [ ] Run `dot update -f` and installed-state tests on the relevant Linux and macOS clients without restarting active sessions; verify the live tmux tab and WezTerm tab if visible, and report any observation limit.
