# Attention dots design

**Invariant format:** tenx/v1

**Spec ID:** dotfiles-attention-dots

Supersedes `2026-10-30-working-tab-spinner-design.md`.

## Intent

Replace the animated working spinner, the orange pending `●` and the red
failed `!` in tmux window tabs, tmux pane borders and WezTerm tabs with static
colored dots that say what an agent needs:

| Dot | State | Meaning | Clears when |
| --- | --- | --- | --- |
| red | blocked | an agent turn died (API error, rate limit) | the agent resumes or ends |
| red | failed | a long shell command failed | you look |
| yellow | waiting | the agent needs an answer: permission prompt, question, plan approval | the agent resumes or ends |
| green | done | a turn finished and you have not looked | you look |
| blue | working | a turn is running | the turn ends |

The spinner redraws tmux status about seven times a second and WezTerm tabs on
a 150 ms timer while any agent works, which makes the cursor flicker. Static
dots change only on state transitions.

Also stop Claude's `idle_prompt` notification (sent about 60 s after a turn
ends or a prompt is dismissed with Esc, never after Esc interrupts a running
tool) from ringing the bell and re-raising attention after every turn: it
fired 992 times in recent telemetry. Its existing role as the repair for a
turn that ended without `Stop` (Esc) stays.

## Goals

- One vocabulary from hook to tab: blocked, waiting, done, failed, working.
- A glance acknowledges only informational dots (done, failed). Dots that need
  an action (waiting, blocked) persist until the agent moves on.
- Nested tmux and SSH/ET layers bubble the same distinction up to the parent
  tmux tab and to WezTerm.
- No animation, no per-server helper process, no WezTerm frame timer.

## Non-goals

- Cross-session "jump to most urgent" summaries (separate idea).
- Classifying an agent's final message text to guess blocked/waiting.
- Detecting question tools from PreToolUse: Claude already sends
  `permission_prompt` for `AskUserQuestion` and `ExitPlanMode` (50 of 50 in
  telemetry), so doing both would ring twice.

## Anti-goals

- New forks on the per-tool hook path (PreToolUse) when nothing is waiting.
- A dot that sticks after its agent is gone.
- A mixed-version rollout that loses attention that works today.
- Leaking host, employer or work-specific names into any repository.

## Ownership and approach

The existing layering is kept; each repository owns the same concern as today.

- **tmux-tools** owns the mark vocabulary (`term-pane-mark`,
  `term-notify-sound`) and the snapshot publisher (`term-pane-state`).
- **AgentGuard** decides which agent event means which kind.
- **termnav** carries counts across layers.
- **Base dotfiles** owns presentation and the acknowledgement policy (tmux
  focus hooks, tab/border formats, `prefix a`, WezTerm tab formatter).

Approaches considered:

1. Separate pane options per kind (`@term_waiting`, `@term_blocked`): more
   options, and every publisher must clear the others.
2. A new state-machine helper (`tmux-agent-state` style, as in the post that
   inspired this): duplicates AgentGuard's turn/token machinery.
3. **Kind as the value of the existing pending option (chosen).** Old
   renderers still see a truthy pending value, new renderers color by value,
   and one option update stays atomic in a single tmux command queue.

## Design

### Marks (tmux-tools)

- `@term_notify_pending` keeps its meaning (attention exists); its value is
  now the kind: `done`, `waiting` or `blocked`. Readers treat the legacy value
  `1` as `done`. `@term_notify_exit_status` still marks a failed shell command
  and only applies to kind `done`.
- `term-pane-mark set pending [--kind done|waiting|blocked]`; default `done`.
  `--exit-status` is accepted only with kind `done`. Unknown kinds exit 64.
- `term-pane-mark clear pending --if waiting|blocked|sticky` clears only when
  the current value matches (`sticky` = waiting or blocked), compared and
  cleared in one tmux command queue on the exact pane id, as busy clears do.
- `term-pane-mark reset busy --owner PID` (the shell prompt's killed-child
  cleanup) also clears sticky pending in the same queue.
- `term-notify-sound --kind K` passes the kind through.
- Owner (`--owner PID`) and pane-resolution rules are unchanged. A newer kind
  replaces an older one; `done` from a Stop replaces `waiting`.
- `AGENTS.md`, README and man pages document the value vocabulary.

### Effective state and counts

Per pane, the effective state is the first match of: red (failed exit status
or blocked), yellow (waiting), green (done), blue (working), none. The
embedding tmux config supplies the predicates, as today; `term-pane-state`
adds a `@pane_waiting` predicate (absent in older configs, so 0) and counts
`working` only for panes without attention. Wire fields: `pending` = red +
yellow + green panes, `failed` = red panes, `waiting` = yellow panes, with
`failed + waiting <= pending`; consumers derive green as
`pending - failed - waiting`. Counting is done after the existing
client-pane substitution.

Sticky kinds render only while the pane is not back at a shell prompt,
matching how busy is hidden today.

### Cross-layer transport (termnav)

- `termnav tmux attention` accepts an optional `--waiting N` (default 0) and
  validates `failed + waiting <= pending`.
- The relay attention request and the `TERM_PANE_STATE` user variable carry
  `waiting` as an additional field; readers treat a missing field as 0.
- The parent-pane lease `@termnav_child_attention` keeps its exact 4-field
  format. Waiting travels in a separate lease option
  `@termnav_child_waiting` = `expiry:N`, written in the same tmux command,
  with the same receiving-host expiry, and removed when N is 0. Old readers
  ignore it, so a not-yet-updated layer shows yellow as green and loses
  nothing else.
- `docs/reference.md`, the man page and `State` docs drop "work and
  attention remain independent" in favor of "counts are per-pane effective
  states chosen by the publisher".

### Agent events (AgentGuard)

| Event | Result |
| --- | --- |
| Notification `permission_prompt`, `elicitation_dialog` (either key spelling: `notification_type` / `notificationType`); Muse `question_prompt` (its `request_user_input` dialog); Codex `PermissionRequest`; OpenCode `permission.ask` | bell, kind `waiting` |
| Notification `idle_prompt` | clear `waiting` (Esc at a prompt); bell `done` only if it wins the existing one-bell-per-prompt-cycle claim (backstop for a Stop that did not ring); repair busy as today |
| Notification `auth_success` | nothing |
| any other Notification | bell, kind `done` (as today) |
| root `StopFailure` | bell `blocked` if it wins the cycle claim; busy clear as today |
| Stop that notifies | bell `done`, as today; replaces any sticky kind |

Sticky bookkeeping:

- After a sticky mark is accepted, AgentGuard writes a per-session flag file
  `attention-sticky` containing the kind and the actor (`root` or the child
  `agent_id`). Set the mark first, then write the flag. Clearers remove the
  flag first, then clear the mark.
- Root PreToolUse tests only `[ -e flag ]` (no fork) and, when present and
  the actor matches the tool's actor, clears `--if waiting`.
- A child's `SubagentStop`/`StopFailure` clears a waiting mark that child
  raised.
- The `PostToolUse`/`PostToolUseFailure` of the prompted tool itself also
  clears a waiting mark (one `[ -e flag ]` test when nothing is sticky): the
  prompted tool cannot return before its prompt is answered, but a parallel
  sibling's result can. Every `PermissionRequest` records
  `<epoch> <actor> <tool>` in a per-session `attention-request` file, where
  the tool is its name plus a hash of `tool_input` without `description`,
  `answers` and `annotations`. A `permission_prompt` whose actor matches a
  fresh record, or a Codex `PermissionRequest`, raises with that fingerprint
  in `attention-tool`, and only a result with the same actor and fingerprint
  clears. A prompt without one (elicitation, Muse question, OpenCode,
  Gemini, stale record) is not cleared by tool results.
- Claude's permission Notification names no `agent_id`, even for a subagent.
  Claude's `PermissionRequest`, which carries it and precedes the
  Notification by about 6 s, is recorded as above and raises nothing. The Notification uses that
  actor when the record is at most 60 s old, else actor `any`, which every
  actor's activity clears (also used for `elicitation_dialog`). Two actors
  requesting within the window can be confused; the newer one wins.
- Prompt submit, a Stop that does not ring, Interrupt and SessionEnd clear
  `--if sticky` when the flag exists, for foreground activity only. The Stop
  clear runs inside the existing attention lock and current-turn check.
- Sticky sets from Notification also run under the attention fence so a late
  notification cannot overwrite a newer turn's state.
- Muse runs no tool hooks for `request_user_input`, so an answered
  question's `waiting` clears at the root's next tool or its Stop.
- Gemini reports tools as `BeforeTool`, which telemetry does not observe;
  its yellow lasts until the turn ends. Documented limitation.

Known limitation: after you approve a permission prompt, yellow stays until
the approved tool returns (or the agent's next tool call or turn end),
because no hook reports the answer itself. While you are focused on that
pane no dot is shown.

### Presentation (base dotfiles)

- Remove the spinner completely: `.local/bin/term-tab-spinner`,
  `.config/terminal/working-spinner.frames`, the spinner `run-shell`, hook and
  options in `10-base.conf`, the frames copy in
  `merge-hooks.d/wezterm.sh`, its `.github/shellcheck-files.txt` entry, the
  spinner tests and support files, and the README text. Mark the old spinner
  spec superseded.
- Window tabs show one dot per effective state present in the window, in
  red, yellow, green, blue order, including child-layer leases. Pane borders
  show the pane's dot; a failed command keeps `exit N` after the red dot.
- Focus hooks clear only non-sticky pending (done, failed); they also clear a
  sticky mark on a pane that no longer runs an agent. Every hook targets the
  exact pane it acknowledges.
- The focused leaf never displays its own dot, as pending is hidden there
  today.
- `prefix a` jumps through panes with displayable attention, most severe
  first, skipping the current pane so repeated presses cycle.
- WezTerm: remove the frame loader and frame timer; render the same dots from
  the snapshot counts. Keep the one-second reconciliation and the redraw
  toggle.
- Colors from the night-owl palette already in use: red `#ff5370`, yellow
  `#ffcb6b`, blue `#82aaff`; green is Night Owl's terminal green `#22da6e`,
  which reads apart from the yellow. The current tmux tab is bright
  underlined text with no fill; the dots follow it on the status-bar
  background, never underlined.
- The tmux README's note is made precise: a busy mark clears only when Claude
  emits `idle_prompt` (about 60 s after a turn ends or a prompt is dismissed
  with Esc); after Esc during a running tool no hook fires, so busy stays
  until the next prompt or turn.

### Compatibility

- AgentGuard retries `term-notify-sound` without `--kind` when an older
  tmux-tools exits 64 (old behavior: bell + plain pending) and then writes no
  flag. A `clear --if` that exits 64 is not retried; AgentGuard just removes
  its flag, because a plain clear would erase unseen done/failed marks.
- `term-pane-state` passes `--waiting` to termnav and retries without it on
  exit 2.
- New readers accept old snapshots (no `waiting`, value `1`).

## Requirements

### REQ-001: Static dots replace the spinner

**Applies when:** Any tmux window or WezTerm tab contains a pane whose
effective state is red, yellow, green or blue, locally or through nested
layers.

**Obligation:** The tab MUST show static colored dots for the effective
states present and MUST NOT animate.

**Acceptance criteria:** No spinner helper, frames file, spinner hook, spinner
option, merge-hook copy or WezTerm frame timer remains; tab text changes only
when a pane's effective state changes.

**Verification needs:** Source inspection plus the dotfiles tmux, WezTerm and
client-extension suites updated to assert dot output for each state.

### REQ-002: Pending kinds are recorded atomically

**Applies when:** A publisher sets pending with a kind, or clears it
conditionally.

**Obligation:** `term-pane-mark` MUST store the kind as the value of
`@term_notify_pending` and MUST perform conditional clears as a single
compare-and-clear in one tmux command queue on the exact pane id.

**Acceptance criteria:** `set pending --kind waiting` stores `waiting`;
`clear pending --if sticky` removes `waiting`/`blocked` and leaves `done` or a
failed mark untouched; unknown kinds exit 64.

**Verification needs:** tmux-tools tests against a private tmux server.

### REQ-003: A glance acknowledges only informational dots

**Applies when:** The user focuses, selects or returns to a pane.

**Obligation:** The tmux focus hooks MUST clear done and failed attention on
that exact pane and MUST NOT clear waiting or blocked attention on a pane
that still runs an agent.

**Acceptance criteria:** After focus-in, a done pane shows no dot; a waiting
pane shows yellow again once focus leaves it; focus-out clears the pane
losing focus, not the one gaining it.

**Verification needs:** dotfiles tmux test on a private server.

### REQ-004: Sticky dots end with the agent's next activity

**Applies when:** An agent with a sticky mark submits a prompt, starts a root
tool, stops, fails, is interrupted, reports idle (waiting only), ends its
session, or the child that raised it stops.

**Obligation:** AgentGuard MUST clear the sticky mark for that pane, and MUST
NOT add a fork to root PreToolUse when no sticky flag exists.

**Acceptance criteria:** Hook tests show the clear for each event; the perf
regression suite shows unchanged fork/jq counts for PreToolUse without a flag.

**Verification needs:** AgentGuard session and perf-regression suites.

### REQ-005: Sticky dots never outlive their agent

**Applies when:** A pane with a sticky mark returns to a shell prompt, or
later runs a program that is not an agent.

**Obligation:** The tmux formats MUST NOT display sticky dots for a pane at a
shell, and the shell's busy reset or a focus visit MUST clear them once the
agent is gone.

**Acceptance criteria:** A waiting mark on a pane running `zsh` renders no
dot; after the reset or a visit it is gone, and running `vim` there later
shows no dot.

**Verification needs:** tmux-tools reset test; dotfiles tmux test.

### REQ-006: Permission prompts and questions are yellow

**Applies when:** An agent raises a permission or question notification.

**Obligation:** AgentGuard MUST ring and set pending kind `waiting` for the
listed types and keep kind `done` for unlisted types.

**Acceptance criteria:** Claude `permission_prompt`, Codex
`PermissionRequest` and a camelCase `notificationType` permission each produce
`--kind waiting`; an unknown type produces `--kind done`.

**Verification needs:** AgentGuard hook tests with notifier fixtures.

### REQ-007: Idle notifications no longer re-raise attention

**Applies when:** An agent sends `idle_prompt` or `auth_success`.

**Obligation:** AgentGuard MUST NOT ring for them unless `idle_prompt` wins
the prompt-cycle bell claim, MUST clear `waiting` on `idle_prompt`, and MUST
keep the existing idle busy repair.

**Acceptance criteria:** After a Stop that rang, `idle_prompt` makes no
notifier call; after a Stop that did not ring, it rings once; existing
idle-backstop tests still pass.

**Verification needs:** AgentGuard notification and session tests.

### REQ-008: Failed turns are red until resumed

**Applies when:** A root agent turn ends with `StopFailure`.

**Obligation:** AgentGuard MUST ring and set pending kind `blocked` in
addition to the existing busy clear.

**Acceptance criteria:** Root `StopFailure` produces `--kind blocked`; a
child `StopFailure` does not.

**Verification needs:** AgentGuard telemetry hook tests.

### REQ-009: Waiting crosses terminal layers

**Applies when:** A nested tmux, SSH or ET layer publishes attention to its
parent pane or terminal.

**Obligation:** termnav MUST carry the `waiting` count through the relay,
the separate `@termnav_child_waiting` lease and `TERM_PANE_STATE`, leaving
`@termnav_child_attention` byte-for-byte in its current format.

**Acceptance criteria:** A child with one waiting pane makes the parent tab
yellow; a snapshot or request without `waiting` is accepted with waiting = 0.

**Verification needs:** termnav tests and Python peer interop; tmux-tools
`term-pane-state` tests.

### REQ-010: Mixed versions degrade, never lose attention

**Applies when:** Any producer runs against an older consumer, or the
reverse.

**Obligation:** Producers MUST retry without new flags only where that
cannot erase other marks, and consumers MUST ignore unknown fields.

**Acceptance criteria:** AgentGuard against a fixture that rejects `--kind`
still rings; a rejected `clear --if` clears nothing; `term-pane-state`
against a termnav that rejects `--waiting` still publishes; an old
`term-pane-state` keeps child working/pending/failed counts from a new
termnav.

**Verification needs:** Compatibility fixtures in each suite.
