# Failed command attention implementation plan

> Use the approved conversation design: distinguish failed long-running shell commands from ordinary attention notifications.

**Goal:** A failed long command shows a red `!` in its window tab and `! exit N` in its pane border until acknowledged.

**Architecture:** tmux-tools owns publication and validation of exit status through its existing notifier and pane marker. Dotfiles forwards shell status and renders the result with pure tmux formats. Existing thresholds, ownership checks, sound delivery, and attention navigation remain authoritative.

**Constraints:** Bash 3.2 compatibility in tmux-tools; shared Bash/Zsh prompt contract; tmux stays at 3.6b; isolated tests only; no new pollers. Normal/zero-status notification replaces stale failure metadata. Failure outranks other pending/busy panes in a window. Focus acknowledgment clears pending and its exit status together.

## Task 1: Provider publication

- [x] Add failing public-interface tests for optional `--exit-status CODE`, 0/255 boundaries and invalid 256/nondecimal values, ownership, stale-state replacement, and pending clear.
- [x] Extend term-notify-sound and term-pane-mark with validated decimal shell exit status 0..255 and pane metadata `@term_notify_exit_status`.
- [x] Update both man pages and run provider tests and CI-equivalent local checks.

## Task 2: Consumer and presentation

- [x] Add failing Bash/Zsh prompt forwarding assertions and real-tmux rendering/acknowledgment cases.
- [x] Forward `--exit-status` only after existing duration/focus gating.
- [x] Render failure before generic pending/busy state; include status in border; clear metadata in every existing acknowledgment hook.
- [x] Update shell/tmux usage docs; run focused suites, format/lint, and full dot test.

## Task 3: Review and delivery

- [x] Independently review provider correctness and consumer side effects.
- [x] Exercise actual provider plus consumer in an isolated tmux server and inspect live version/config preservation.
- [x] Report tested changes and installation state accurately.

Validation: provider public-interface tests 267/0; all four provider suites pass; dotfiles 35 suites pass, one skip. Independent correctness and side-effect reviews are clean after atomic publication and style-reset fixes. Actual provider/consumer integration passed on an isolated tmux 3.6b server. Installation awaits integration of both branches, provider first.
