# Remote image paste design

**Invariant format:** tenx/v1

**Spec ID:** dotfiles-remote-image-paste

## Intent

Pressing Ctrl-V in WezTerm while the clipboard holds an image (a screenshot)
should give the coding agent in the active tmux pane that image, whether the
agent runs on this desktop or on a remote host: through local tmux layers and
one remote hop over any interactive transport the setup uses (SSH, Eternal
Terminal), the same reach termnav's link opening has.
Agents such as Claude Code attach an image when its file path is pasted, so
the result is: the image is saved as a PNG on the host where the innermost
tmux runs, and its absolute path is bracket-pasted into that pane.

Today WezTerm intercepts Ctrl-V and pastes text only, so an image paste does
nothing, locally or remotely.

## Goals

- Ctrl-V with an image works in local and remote tmux panes; Ctrl-V with text
  is unchanged everywhere, with no added latency.
- Works over every transport that carries keystrokes, including Eternal
  Terminal, with no tunnel, port forward, login, daemon or host knowledge.
- The desktop never exposes a clipboard read service. Only WezTerm pushes,
  and only after the user pressed Ctrl-V on that pane.

## Non-goals

- Remote panes without tmux (a bare SSH shell running the agent): Ctrl-V there
  keeps pasting text.
- mosh, which is unsuitable for multi-megabyte input: declined with a message.
- Chains with more than one remote hop (termnav's outward user-variable path
  wraps one passthrough frame per uninspectable layer).
- A clipboard holding both text and an image: the text is pasted, as today.
- VS Code's integrated terminal, which intercepts Ctrl-V itself.
- Image formats other than PNG.

## Known limitations

Accepted and documented; remote tmux running this configuration is the
supported setup.

- Forwarding over SSH or Eternal Terminal trusts mouse reporting, the gate
  pane navigation already uses. When the mouse-aware program on the far side
  is not tmux, the trigger reaches it as input: remote Neovim in insert mode
  inserts a stray character, and Vim inserts a stray character and leaves
  insert mode.
- A remote or nested tmux that has not yet reloaded this configuration has
  no `user-keys[14]` and passes the trigger to its application as
  `^[[777010u`. This is a rollout window that closes when the remote host's
  scheduled update reloads tmux.

## Anti-goals

- Any remote process obtaining a desktop clipboard image without a fresh user
  gesture on the pane that leads to it.
- Base64 or any other transfer bytes reaching an application pane.
- Blocking WezTerm's GUI thread.
- Host-, employer- or tunnel-specific names in these public repositories.

## Approaches

1. Push with a separate `scp`/`ssh` upload (as in the post that inspired
   this): needs host discovery, can prompt for a second login, and breaks
   termnav's "never open a second authenticated transport" invariant.
2. Pull over termnav's SSH relay: replies are capped at 512 bytes and
   serialized; the relay exists only for `termnav ssh`, so Eternal Terminal
   sessions (the main remote path in this setup) would never get it; and a
   pull service lets any same-user remote process ask for the clipboard.
3. **In-band push through the terminal stream (chosen).** WezTerm already
   owns the pane's input. After a handshake proving a receiver is listening in
   the innermost tmux, WezTerm types the base64 PNG into a short-lived tmux
   popup there. A private-server spike moved 6 MB through a tmux popup intact
   in about 4.7 s.

## Design

### Flow

1. **Gesture (WezTerm).** Ctrl-V always performs the normal text paste first,
   immediately. Then, only for a pane whose terminal owner is tmux, a
   scheduled callback runs `termnav paste-image stage`. It exits 3 unless the
   clipboard holds a PNG-convertible image and no text, so text and mixed
   clipboards behave exactly as today. On success WezTerm arms that pane for
   10 s with the staged file and sends the private trigger key
   `\033[777010u` (tmux `user-keys[14]`, next to termnav's existing
   `user-keys[8]`).
2. **Routing (each tmux layer).** A layer declines with a `display-message`
   when its active pane is in a mode (`pane_in_mode`) or panes are
   synchronized. It forwards the trigger inward with `send-keys -H` when the
   active pane runs SSH, Eternal Terminal or tmux with mouse reporting on (a
   dedicated predicate: unlike pane navigation, a local editor or fzf never
   receives it). It declines mosh, and SSH/ET with mouse reporting off.
   Otherwise this layer is innermost and opens a small popup running
   `termnav paste-image receive` for that pane and client. Mouse reporting
   over SSH/ET is the same gate pane navigation uses, and it cannot tell a
   remote tmux from another mouse-aware program: a forwarded trigger that
   reaches a remote editor or a remote tmux without this configuration is
   typed into the application (see the known limitations). No `ready` comes
   back, so no image data follows.
3. **Handshake.** The receiver generates a random id (16 lowercase hex
   digits; WezTerm accepts 8 to 64) and announces `ready:<id>` in the user
   variable `TERMNAV_PASTE_IMAGE` through termnav's exact-client outward user-variable path
   (the one `request_click` uses, given `--client-pid/--client-tty`), never
   the session's most recent client.
4. **Transfer with flow control.** WezTerm accepts `ready` only from the
   armed pane, once, before expiry. The transfer is
   `<id>:<length>:<sha256>:<base64>!`: `<length>` is the decoded PNG size
   (8 to 16777216, no sign or leading zero), `<sha256>` is 64 lowercase hex
   digits, and `<base64>` is standard padded base64 on one line. Until the
   first proven acknowledgement WezTerm types only the header
   `<id>:<length>:<sha256>:` (at most 139 bytes of digits, hex and colons),
   never image data. The receiver announces `ack:<id>:<offset>:<proof>` right
   after the header and then at least every 128 KiB: `<offset>` counts the
   transfer bytes it accepted from the first id byte and strictly increases,
   and `<proof>` is the first 16 hex digits of the SHA-256, which only a
   reader of the typed header can know. WezTerm accepts an acknowledgement
   only from the transfer's pane, with its id, the proof and an offset it
   already sent. It keeps at most 512 KiB in flight beyond the last proven
   acknowledgement and types at most 32 KiB per timer callback. Each
   announcement is a distinct value (WezTerm fires `user-var-changed` only on
   change). After 5 s without an acknowledgement WezTerm sends `!` and
   abandons the transfer.
5. **Delivery.** The receiver reads its raw stdin, rejects the first byte
   outside the header or base64 grammar, checks id, length, SHA-256, the size
   cap and the PNG signature, writes the image privately, announces
   `done:<id>`, closes the popup and bracket-pastes the absolute path into the
   target pane. On any failure it announces `cancel:<id>`, shows a message and
   writes nothing, and keeps in-flight bytes from reaching the pane: input
   whose first byte is a hex digit but whose id is wrong is a foreign
   transfer, drained until `!` or 30 s; any other first byte (Esc, for
   example) is a user keystroke, and it waits for 1 s of quiet. WezTerm sends
   `!` as soon as it sees a `cancel` from the transfer's pane, whatever its
   id.
6. **Cleanup.** WezTerm deletes the staged file on done, cancel, abandonment
   or expiry; `stage` prunes stale staged files it owns.

Bounds: if focus moves to another pane mid-transfer, at most the current
window (512 KiB beyond the last proven acknowledgement) can reach that pane's
application before acknowledgements stop; before the first proven
acknowledgement, only the header can.

### termnav (owns the protocol, both endpoints and the WezTerm module)

- `termnav paste-image stage`: reads a PNG from the desktop clipboard with a
  bounded subprocess (macOS: `osascript` reading the pasteboard's PNG class
  into a private temp file; Linux: `wl-paste --type image/png` when Wayland is
  usable, else `xclip -selection clipboard -t image/png -o` when X is usable),
  checks the PNG signature and a 16 MiB cap, writes the header and base64 text
  to a 0600 file in termnav's private runtime directory and prints its path.
  Exit 3 when the clipboard holds no PNG or also holds text. The clipboard
  reader programs get 5 s in total; encoding and writing are not timed.
  Staged files older than 10 minutes are pruned.
- `termnav paste-image receive --target-pane PANE --client-name NAME
  [--client-pid PID --client-tty TTY]`: the popup endpoint described above.
  Writes `clip-<UTC timestamp>-<random>.png` (0600) under
  `$XDG_CACHE_HOME/termnav/paste-images` (0700, owner-checked, no symlinks),
  prunes its own files older than 7 days, shows progress, and gives up after
  30 s without progress. Never writes partial files.
- WezTerm Lua module `lib/termnav/wezterm/paste-image.lua`, wired by the
  dotfiles the same way as `link-routes.lua`: a Ctrl-V action and a
  `user-var-changed` handler for `TERMNAV_PASTE_IMAGE`.
- The trigger key sequence, user-variable name and message grammar are
  documented in `docs/reference.md` and the man page.

### Base dotfiles

- `wezterm.lua`: Ctrl-V uses the termnav action; Cmd-V on macOS stays a plain
  text paste.
- `10-base.conf`: define the trigger as a `user-keys` entry and bind it with
  the routing rule above. The existing `C-v` binding is unchanged.

### Security

The desktop serves nothing on request. A remote process can only cause an
image to be sent by announcing `ready` while WezTerm is armed for the pane
that leads to it, which needs the user's Ctrl-V there within the last 10 s,
and only once. Another visible pane, or a same-user process that can write
the client tty, can still forge `ready` during that window, but it gets only
the header: advancing past it needs the proof, which only a reader of the
focused pane's input learns. Residual risk, accepted and documented: whatever
reads the focused pane's input (the real receiver popup, or an application
the trigger was forwarded into) can obtain the image, which is equivalent to
a text paste to that host.

## Requirements

### REQ-001: Image paste works locally and remotely

**Applies when:** The desktop clipboard holds a PNG-convertible image and the
user presses Ctrl-V in WezTerm on a tmux pane, local or behind SSH, Eternal
Terminal or nested tmux layers that run this configuration.

**Obligation:** The image MUST be saved as a PNG on the host where the
innermost tmux runs and its absolute path MUST be bracket-pasted into the
pane that was active there.

**Acceptance criteria:** One PNG byte-identical to the clipboard image appears
in that host's private image directory and the pane receives its path once.

**Verification needs:** termnav tests of stage and receive with a fake
clipboard adapter and a private tmux server, including a nested tmux layer
and a 16 MiB payload timing; one manual end-to-end run from the desktop over
SSH and Eternal Terminal.

### REQ-002: Text paste is unchanged

**Applies when:** The clipboard holds no image, the pane is not tmux-owned,
or the user presses Cmd-V.

**Obligation:** WezTerm MUST paste text exactly as before.

**Acceptance criteria:** WezTerm performs `PasteFrom("Clipboard")`
immediately on every Ctrl-V and Cmd-V, before any probe, and starts the image
flow only for an image-only clipboard.

**Verification needs:** dotfiles WezTerm test of the action decision.

### REQ-003: WezTerm sends only after its own gesture and handshake

**Applies when:** WezTerm receives a `TERMNAV_PASTE_IMAGE` user variable.

**Obligation:** WezTerm MUST start a transfer only for a `ready`
announcement from the pane it armed, within 10 s of arming, and at most once
per arm, and MUST type image data only after a proven acknowledgement.

**Acceptance criteria:** Unarmed, expired, repeated or other-pane
announcements send nothing. Before the first proven acknowledgement only the
header is typed. Acknowledgements from another pane, or with a wrong id, a
wrong proof or an offset not yet sent, are ignored.

**Verification needs:** WezTerm module test with a stubbed pane.

### REQ-004: Transfer bytes never reach an application

**Applies when:** Any tmux layer receives the trigger key or transfer data.

**Obligation:** Routing MUST forward the trigger only into a nested terminal
that runs tmux, as far as mouse reporting can tell (see Known limitations),
and WezTerm MUST NOT send data before a receiver announced `ready`.

**Acceptance criteria:** A local pane running a shell or an editor, a pane in
copy mode and a synchronized window receive neither the trigger nor data;
mosh and mouse-off SSH/ET are declined with a message; the header starts only
after `ready`, image data only after a proven acknowledgement, and data stays
within the acknowledgement window.

**Verification needs:** dotfiles tmux routing test on a private server.

### REQ-005: Transfers are bounded and validated

**Applies when:** Image bytes are staged, received or written.

**Obligation:** termnav MUST enforce the 16 MiB cap, the PNG signature, the
id, length and SHA-256 header checks, the 5 s clipboard reader budget and the
30 s idle limit, and MUST write only into a private directory with 0600
files.

**Acceptance criteria:** Oversized, non-PNG, truncated or mismatched payloads
leave no file and announce `cancel`; a non-private output directory is
refused.

**Verification needs:** termnav unit and integration tests.

### REQ-006: WezTerm stays responsive

**Applies when:** Staging or sending runs.

**Obligation:** The WezTerm module MUST NOT run a subprocess or a multi-chunk
send on the synchronous key or event path.

**Acceptance criteria:** Staging runs from a scheduled callback; data is sent
from timers in chunks of at most 32 KiB.

**Verification needs:** Source inspection and the WezTerm module test.
