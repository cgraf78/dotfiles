# VS Code tab-switching consistency design

> **Post-implementation design change (2026-07-06, live testing):** the
> bubble-up target moved from editor tabs to integrated-terminal tabs.
> Where this document says the terminal-focus bubble-up switches/moves
> *editor* tabs, the shipped behavior is: `Ctrl-Tab`/`Ctrl-Shift-Tab`
> bubble to `workbench.action.terminal.focusNext`/`focusPrevious` (the
> terminal tab list) and stop there; `Alt-Shift-[`/`]` moves stop at the
> tmux layer entirely, because VS Code exposes no command to reorder
> terminal tabs (drag-only — confirmed against the live command list).
> `vscode-move-tab` was removed from termnav accordingly. Editor-focus
> behavior (the table's left column) is unchanged.

## Background

`Ctrl-Tab`, `Ctrl-Shift-Tab`, `Alt-Shift-[`, and `Alt-Shift-]` already work
consistently across tmux, WezTerm, and nvim: they switch/move tabs at
whichever layer currently owns them, and bubble up to the next layer out when
the current layer has nothing left to switch (tmux's "outer WezTerm" bridge in
`~/git/termnav`'s `wezterm-switch-tab`/`wezterm-move-tab`, driven by OSC 1337
`SetUserVar` escapes that WezTerm's Lua config listens for).

VS Code's integrated terminal is the one place this isn't consistent yet:

1. **Editor-focus gap**: in `~/.config/dot/merge-hooks.d/vscode/keybindings/all.d/10-keybindings.jsonc`,
   `Ctrl-Tab`/`Ctrl-Shift-Tab` already have a `!terminalFocus` rule that
   switches editor tabs (VS Code's own MRU editor-switch commands) when the
   editor region is focused. `Alt-Shift-[`/`Alt-Shift-]` only have a
   `terminalFocus` rule (forwarding to the shell) — there's no editor-focus
   counterpart to move editor tabs.
2. **Bubble-up gap**: the existing bubble-up scripts speak WezTerm's
   proprietary OSC 1337 protocol, which VS Code's terminal (xterm.js) doesn't
   understand at all. When tmux has one window (or nvim has one buffer) and
   wants to bubble the keypress out to "switch/move the container's own tabs,"
   inside VS Code's terminal this is silently a no-op today.

A related, separately-shipped bug (commit `fb3e5cb2`) is *not* part of the
remaining work here: tmux's `Ctrl-Tab`/`Ctrl-Shift-Tab`/`Alt-Shift-[`/`Alt-Shift-]`
bindings were being swallowed whenever `#{mouse_any_flag}` was set on the
foreground pane, regardless of whether that pane's program actually wanted to
own the chord — any TUI enabling mouse reporting for its own purposes (Claude
Code CLI, codex, etc.) tripped this. That's already fixed and deployed
independently. This spec covers the remaining consistency and bubble-up work.

## Goals

- `Ctrl-Tab`, `Ctrl-Shift-Tab`, `Alt-Shift-[`, `Alt-Shift-]` all behave
  consistently in VS Code: switch/move editor tabs when the editor region is
  focused, forward to the shell when the terminal is focused (already true for
  the first two; needs adding for the bracket chords).
- The terminal-focus bubble-up case (tmux/nvim have nothing left to switch
  locally) works in VS Code the same way it already works in WezTerm.
- When the same tmux session is attached from both a VS Code window and a
  WezTerm window simultaneously, bubble-up routes to whichever app the
  keypress actually came from — not a hardcoded/stale guess.
- The VS Code bridge mechanism is swappable: today it's implemented via the
  already-installed `nabheet.vscode-ide-mcp` extension's HTTP API, but the
  interface is a single seam so a different mechanism can be substituted later
  without touching callers.
- Config changes are durable in dotfiles/termnav source and deployed via
  `dot update` to the whole fleet, not hand-patched on one machine.

## Non-goals

- Multiple simultaneous VS Code windows connected to the same remote host at
  once (only "one VS Code window + one WezTerm window on the same session" is
  in scope, per explicit user framing). If it happens anyway, behavior is
  unspecified best-effort — the bridge hits whichever port it's configured
  for, which may not be the window you're bubbling up from. Not a supported
  guarantee, not a crash risk either.
- Port-scanning the MCP extension's ±5 retry range if its default port is
  ever unavailable — accepted as a rare, silently-failing edge case.
- Any change to the MCP extension itself (third-party, not owned by this repo).

## Architecture

Four chords, two contexts, in VS Code:

| Chord | Editor focus | Terminal focus |
|---|---|---|
| `Ctrl-Tab` | next editor tab (MRU) — already works | forward to shell — already works |
| `Ctrl-Shift-Tab` | previous editor tab (MRU) — already works | forward to shell — already works |
| `Alt-Shift-[` | **add**: move editor tab left | forward to shell — already works |
| `Alt-Shift-]` | **add**: move editor tab right | forward to shell — already works |

Terminal-focus forwarding already reaches tmux/nvim correctly (verified
end-to-end during the mouse-flag bugfix investigation, using the exact CSI-u
byte sequences VS Code's keybindings send). What's missing is what happens
when tmux/nvim, having received the forwarded chord, have nothing local left
to switch and need to bubble further out.

## Components

### 1. `all.d/10-keybindings.jsonc` (dotfiles)

Add, mirroring the existing `Ctrl-Tab`/`Ctrl-Shift-Tab` pattern exactly
(negate-then-readd with a `!terminalFocus` guard):

- `alt+shift+[` → `workbench.action.moveEditorLeftInGroup`, `when: "!terminalFocus"`
- `alt+shift+]` → `workbench.action.moveEditorRightInGroup`, `when: "!terminalFocus"`

**Open item**: confirm whether VS Code has a default binding on these exact
chords that needs negating first (couldn't reach `clark2` to check — it was
asleep mid-investigation). Concrete verification step for the implementation
plan, same technique used to find the earlier stray `terminal.focusNext` entry
(inspect the client's live `keybindings.json`, and decode the app's bundled
`workbench.desktop.main.js` default-keybinding registrations if needed).

### 2. `~/git/termnav` — layered VS Code bridge

- **`bin/vscode-switch-tab`** / **`bin/vscode-move-tab`** — stable public
  interface, mirroring `wezterm-switch-tab`/`wezterm-move-tab`. Only know
  about directions (`next`/`previous`/`left`/`right`); translate to VS Code
  command IDs (`workbench.action.nextEditor`, `previousEditor`,
  `moveEditorLeftInGroup`, `moveEditorRightInGroup`). No knowledge of *how*
  the command actually executes.
- **`lib/termnav/shell/vscode-command.sh`** — the swap seam. Exposes one
  function, `termnav_vscode_execute_command <command-id>`, dispatching to
  whichever backend `TERMNAV_VSCODE_BACKEND` selects (default: `mcp`).
  Silent-no-op failure handling lives here once, for every backend.
- **`lib/termnav/shell/vscode-backend-mcp.sh`** — today's only backend. Reads
  the auth token from `${XDG_STATE_HOME:-$HOME/.local/state}/dot/vscode-mcp-auth-token`
  (contract with dotfiles' `vscode.sh`, which writes it), and does the
  JSON-RPC `tools/call` → `execute_command` POST to
  `http://127.0.0.1:<port>/mcp` (port default 9876, overridable via
  `VSCODE_MCP_PORT`, mirroring the extension's own `MCP_PORT`).
  If this backend proves problematic, a new `vscode-backend-<x>.sh`
  implementing the same one-function contract drops in, and only
  `TERMNAV_VSCODE_BACKEND`'s default changes — `bin/vscode-switch-tab`,
  `tmux.conf`, and `nvim` never change.

### 3. `tmux.conf` (dotfiles)

The bubble-up call sites (currently unconditionally calling
`wezterm-switch-tab`/`wezterm-move-tab`) branch on **which client sent this
specific keypress**, using tmux's per-client terminal identity
(`#{client_termtype}`, which reports e.g. `xterm.js(6.1.0-beta.285)` for VS
Code's integrated terminal — confirmed empirically; WezTerm's own value to be
confirmed during implementation) rather than a session-wide environment
variable. Format expansions in a `bind-key -n` binding are already evaluated
in the context of the exact client that triggered it, so this is a drop-in
condition swap (`#{m:xterm.js*,#{client_termtype}}`), not new plumbing.

**Rejected alternative**: branching on the `VSCODE_IPC_HOOK_CLI` environment
variable (forwarded via `update-environment`). Rejected because it's
session-wide, not per-client — if both a WezTerm and a VS Code client are
attached to the same session, whichever attached *most recently* wins for
every pane in the session, regardless of which client actually sent the
keypress. Would misroute bubble-up to the wrong app whenever both clients are
attached simultaneously and you're not currently on the one that attached
last.

### 4. `nvim` (`keymaps.lua`) `smart_tab_switch`/`smart_tab_move`

Same branch, but nvim has no per-event client context (it receives forwarded
bytes with no client-identity metadata attached). Uses the best available
proxy instead: `tmux list-clients -F '#{client_activity} #{client_termtype}'`,
picking the most-recently-active client as "whichever window the user is
actually looking at right now." Calls the new `vscode-switch-tab`/
`vscode-move-tab` scripts instead of `request_wezterm_tab_switch`/`move` when
that client matches the VS Code pattern.

**Async invocation, not synchronous**: the existing WezTerm bubble call
(`vars.set` writing an OSC escape) is synchronous but instant — no I/O wait.
The VS Code path is a real HTTP round-trip over loopback, which can hang on a
dead/slow MCP server. Must invoke via `vim.fn.jobstart` (fire-and-forget, no
callback — matches the no-op-on-failure decision), not `vim.fn.system`, to
avoid freezing the editor.

## Data flow

**Editor focus** (all four chords): entirely inside VS Code, no shell/bridge
involved.

**Terminal focus, tmux has >1 window** (or nvim has >1 listed buffer): VS
Code forwards the raw escape to the shell; tmux's or nvim's existing local
logic resolves it (`next-window`/`previous-window`/`swap-window` or
`BufferLineCycle*`/`BufferLineMove*`). No bridge involved — already works
today, untouched by this work.

**Terminal focus, tmux has exactly 1 window *and* nvim has exactly 1
buffer** (the bubble-up case) — two independent call sites, since nvim's own
keymap fully owns the chord once tmux has forwarded raw input to it:

- **tmux** (foreground is a plain shell): `session_windows == 1` → check the
  triggering client's `#{client_termtype}` → VS Code pattern → `run-shell -b
  vscode-switch-tab next/previous` (or `vscode-move-tab left/right`) instead
  of the WezTerm script; otherwise existing WezTerm path, unchanged.
- **nvim** (foreground is vim, buffer count == 1, `tmux_window_count() <= 1`):
  check the most-recently-active client's `#{client_termtype}` → same branch,
  async `jobstart` call to the new scripts instead of
  `request_wezterm_tab_switch`/`move`.
- Either way: direction → command ID → `termnav_vscode_execute_command` → MCP
  backend → VS Code switches/moves the actual editor tab.

## Error handling

- **Silent no-op on any bridge failure** (extension not running, port
  refused, auth token missing, timeout) — same as today's "nothing to bubble
  to" behavior. This also covers the common case: the MCP server only exists
  while the VS Code window is actively connected, which is exactly when the
  bridge would ever be needed.
- **tmux caller**: `run-shell -b`, already fire-and-forget — never blocks the
  tmux UI regardless of latency.
- **nvim caller**: `vim.fn.jobstart`, not `vim.fn.system` — see Components
  above. Without this, a hung MCP server would freeze the editor.
- **Bounded timeouts**: `vscode-backend-mcp.sh`'s `curl` calls get a hard
  `--max-time` budget (covering the handshake if one turns out to be required
  — see Open items). Bounds background-process lifetime and keeps nvim's async
  job resolving promptly.
- **Auth token missing/unreadable**: fail immediately, no network attempt.
- **Port discovery**: default 9876, override via `VSCODE_MCP_PORT`. No
  scanning of the extension's ±5 retry range (non-goal, above).
- **nvim's client lookup returns nothing**: falls through to no-op.

## Testing

**Automated** (added to `~/git/termnav`'s test suite; one case per edge case):

- `vscode-switch-tab`/`vscode-move-tab`: direction → command-ID mapping.
- `vscode-command.sh`: the backend-selection seam itself — override
  `TERMNAV_VSCODE_BACKEND` to a fake backend in the test and confirm it's
  called, proving the swap point works before it's ever needed for real.
- `vscode-backend-mcp.sh`: request/response shape against a stub local HTTP
  server. Dedicated cases: auth token file missing, connection refused, a
  deliberately slow/hanging stub to confirm the timeout actually bounds it.

**tmux.conf**: extend the isolated `tmux -L` test-server technique used for
the mouse-flag bugfix. The glob-match pattern can be tested against literal
substituted strings without a real client; the full per-client dispatch
(picks the *triggering* client, not some other attached client) needs at
least one live check against a real multi-client session.

**nvim**: confirm the `jobstart`-based invocation doesn't block the editor
(deliberately slow fake backend, check nvim stays responsive). The
"most-recently-active-client" selection verified manually rather than
automated, same reasoning.

**Manual/live verification checklist** (done once implementation lands):

- `Alt-Shift-[`/`]` moves editor tabs when editor-focused, still forwards to
  shell when terminal-focused.
- Same session attached in both VS Code and WezTerm simultaneously:
  bubble-up switches the tab in whichever app you were actually typing into.
- The MCP `initialize`→`tools/call` handshake question gets settled
  empirically against the real extension (see Open items).
- `dot update` on `clark2` (and other client machines) regenerates
  `keybindings.json` correctly; spot-check for the stray-entry class of bug
  already found once (`fb3e5cb2`'s investigation).

## Open items for the implementation plan

All three implementation tasks (5-7) landed with these still genuinely
open — `clark2` stayed unreachable through the entire implementation pass,
and the dotfiles push (needed before `clark2` can even pull the fix via
`dot update`) is deliberately held pending user review. Status as of the
implementation pass:

1. **Still open.** Confirm whether VS Code has default bindings on
   `alt+shift+[`/`alt+shift+]` that need negating. Task 5 shipped without a
   negation entry (per the spec's own contingency for this exact case), and
   the tmux-side comment update (Task 5) plus the actual bridge (Tasks 6-7)
   are both in place and passing 121+93+63 local tests — but this specific
   item can only be confirmed against a live VS Code client.
2. **Still open, but the code handles both outcomes.** Task 2's MCP backend
   tries a direct `tools/call` first and falls back to `initialize` + retry
   only if the response carries a JSON-RPC error — verified against a mocked
   server reproducing both paths, but never against the real
   `nabheet.vscode-ide-mcp` extension (it was never running during
   implementation either, for the same reason as above).
3. **Still open.** No real WezTerm client was attached to a session during
   this implementation pass, so `#{client_termtype}`'s value for WezTerm
   specifically remains unconfirmed — the glob match (`xterm.js*`) is
   VS-Code-specific enough that a collision seems unlikely, but this is
   still a genuine gap, not a formality.

All three require the manual/live verification steps in Task 8 of the
implementation plan, which are blocked on the dotfiles push landing first.
