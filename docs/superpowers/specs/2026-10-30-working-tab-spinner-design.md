# Working tab spinner design

## Intent

Replace the static working `⋯` in tmux window tabs and WezTerm tabs with a
Braille spinner resembling the agent's pane-title animation. Keep pending `●`
and failed `!` visible beside it. A busy pane in an unfocused window, including
leased nested work, must still animate. Aim for a frame every 150 ms; stop
displaying the spinner as soon as the existing working state clears.

## Constraints

- The existing tmux pane predicates and `TERM_PANE_STATE` snapshot remain the
  authority for whether work is active. Animation must not acknowledge work.
- Keep tmux's five-second `status-interval`. A one-second interval gives an
  eight-to-ten-second revolution and runs the per-client snapshot job more
  often even while idle.
- Frequent frame redraws can defer tmux's normal status `#()` jobs. The
  helper must publish each attached client's existing collector snapshot
  once when work begins and every five seconds while it continues.
- A conditional tmux `#()` job scales with attached clients times working
  windows: a private five-client, five-window probe started 25 helpers. One
  server-owned updater is needed instead. Changing a server user option
  immediately redraws tab formats even with a long status interval.
- Keep WezTerm's normal one-second `update-status` reconciliation. Animate
  locally only while a fresh working snapshot exists; do not add a GUI-thread
  subprocess or change the snapshot protocol. The animation callback must
  also reconcile because publishing right status may defer `update-status`.

## Approaches

1. Shorten tmux's global status interval: simple but too slow at its minimum
   one-second step and increases background collection even when idle.
2. Conditional tmux streaming status job plus local WezTerm timer: no new wire
   protocol, but process count and output scale as clients times busy windows.
3. One server-owned tmux frame updater plus a local WezTerm busy-only timer
   (chosen): the updater writes one shared frame option at 150 ms only while
   work exists. It owns takeover on config reload, exits when its tmux server
  disappears, and sleeps between checks while idle. Attached clients share
  one clock and redraw their existing tabs. It keeps their existing snapshot
  lease fresh while frame writes defer status jobs. WezTerm uses a per-window timer
   while working and a one-second reconciliation when idle.

## Display and ownership

Keep the Braille frames in one plain UTF-8 file under `.config/terminal/`;
the tmux Bash helper and WezTerm Lua module both read it. The helper belongs
to the dotfiles base because it implements a personal tab presentation policy.
Do not change tmux-tools or AgentGuard. The tmux config starts one helper on
load and on client attach. Each start replaces a server-side owner token, so
an older helper exits after noticing takeover; no persistent lock files are
needed. Every frame write compares that token inside the same tmux command
queue, so an older helper cannot overwrite a newer one. If the frame file is
missing or a helper exits normally, show static `⋯` rather than an empty
working marker. An untrappable kill can freeze the last frame until a client
attaches or the config reloads; the existing busy predicate still removes it
as soon as work ends. Leave the live pane-border title untouched.

WezTerm's formatter has no GUI-window ID, so it derives the current frame
from a shared millisecond clock. A per-window timer only forces redraw and
reconciles. The timer does not start when frames are unavailable. Config reload
invalidates outstanding callbacks through a per-window token in
`wezterm.GLOBAL`, claimed by the active GUI status callback.

## Verification

Use a private tmux socket and attached PTY to observe multiple frames, an
unfocused busy window, prompt disappearance on clear, one helper despite
multiple clients/windows, takeover on reload, and helper exit after server
loss. Keep all tests away from the live server. Exercise WezTerm's frame
progression, narrow-tab badge reservation, attention precedence, snapshot
expiry, duplicate timer prevention, and a vanished pane. Run full dotfiles
tests plus installed-state checks on the relevant clients. Measure tmux/helper CPU
and collector invocation frequency with five clients and five busy windows;
if the animation is materially costly or visually laggy, adjust before
deployment.

For the five-client/five-busy-window probe, the added sustained CPU budget is
0.15 of one CPU core relative to the same idle setup, and the collector may
run no more than once per client per second after startup. This is a measured
acceptance gate, not an estimate of every host's future workload.
