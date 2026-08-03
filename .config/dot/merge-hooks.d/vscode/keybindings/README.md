# VS Code Keybindings

This directory groups VS Code keybinding source families by platform.

- `all.d/` applies to every VS Code config target.
- `linux.d/` applies on native Linux.
- `macos.d/` applies on macOS.
- `windows.d/` applies on Windows and WSL-backed Windows VS Code targets.

Each directory is a merge-hook family. Direct `*.jsonc` files aggregate in
lexical order, and an immediate `.replace/` group contributes only its last
matching `*.jsonc` file.

Existing local-only bindings keep their normal precedence over managed
bindings. The terminal-native `Ctrl-Tab` and `Ctrl-Shift-Tab` send-sequence
routes are the exception: they are emitted last so an overlapping local handler
cannot consume those chords before the pty. They depend only on `terminalFocus`,
not on the Termnav adapter; native VS Code editor switching remains in control
outside the terminal.
`all.d/00-retirements.jsonc` is append-only exact history. Its
`dotfiles.retire` records are source-only and never reach VS Code. The hook
matches those complete objects rather than guessing ownership from a key,
command, or condition, so a similar local binding remains untouched. Keeping
history in source is deliberate: JSONC comments are not merged semantically by
Settings Sync, while every field that is merged can also affect VS Code's
keybinding resolver or command behavior. Two sealed proof sets cover objects
observed live without prior active-source ownership: PR #90's review build and
the exact legacy terminal-tab handlers recorded in PR #45. Both sets are
canonical in the development-time history guard, which rejects substitutions,
additions, and omissions. Runtime parsing only allowlists their proof labels.
The second set intentionally grants deletion authority over those two local
objects: PR #45 recorded them as obsolete competitors to the managed tab
bridge, and no-Termnav profiles now require native Ctrl-Tab handling. It does
not authorize deleting similar local customizations.

The retirement mechanism understands only its generic schema; it has no list
of Termnav chords, commands, platforms, or focus conditions. Adding a binding
requires editing only its normal JSONC source. When changing or deleting one,
append its former exact object to the common retirement JSONC in the same
change. Keep retirement records indefinitely so a machine that skips releases
can still remove an intermediate generation synchronized from elsewhere.

The merge test enforces the policy against an immutable Git event base for each
effective platform projection, both with and without the Termnav capability. A
removed or changed active object must enter retirement; retirement is
append-only, must live in `all.d` so every platform can remove a synchronized
foreign generation, and must exactly match prior landed active source. These
checks keep deletion authority narrow enough that an invented retirement cannot
consume an identical local-only binding. The sealed `dotfiles.retire-proof`
sets are the only exceptions; the history guard fixes each label and canonical
exact-object set so neither can become a general bypass.

Native paths use an atomic rename. WSL uses the existing verified write with
best-effort rollback because Windows can deny replacement of an open VS Code
file. Malformed retirement records fail closed because guessing at ownership
could either delete a local binding or strand a managed one.

Termnav's local VS Code extension publishes `termnav.nvimFocused` only while
the active integrated terminal and, when present, focused tmux pane are owned
by Neovim. `all.d/20-nvim-focus.jsonc` uses that leased context to pass
VSCode-style chords to Neovim. The extension is the only process sensor in this
layer: VS Code keybinding conditions cannot inspect the foreground process in a
tmux pane by themselves. The adapter expires the lease and publishes false on
terminal changes, terminal disposal, window focus loss, and extension
deactivation, so a stale positive context fails closed.

VS Code treats a context key that was never published as false. That is a
missing capability, not evidence that the workbench owns every chord.
Neovim-specific additions must therefore be positive-only
(`terminalFocus && termnav.nvimFocused`). Do not pair them with negated host
commands for chords that normally reach the terminal; such fallbacks steal
keys whenever the adapter is absent. Existing baseline routes such as terminal
paste, quick open, terminal toggle, tmux prefix and pane navigation, and terminal
tab navigation remain explicit, while other chords use normal VS Code and
xterm.js resolution. Keybinding emission is deliberately
variant-independent. A variant that cannot load the adapter uses `no-termnav`
only to unregister managed adapter generations. The shared file keeps baseline
terminal routes active and leaves only Neovim-specific routes inert while the
context key is false. This is also safe when capable and restricted extension
hosts share one VS Code config directory: both receive identical files, and
runtime context selects only the Neovim-specific behavior.
Without the sensor, Neovim-aware routing is unavailable, but normal editor and
workbench behavior continues outside the terminal, while terminal-native
controls continue reaching shell and tmux.

The common terminal-native inventory is intentionally narrow: `Ctrl-B` for the
tmux prefix, `Ctrl-H/J/K/L` for tmux pane navigation, and both `Ctrl-Tab`
directions for layered tab navigation. Clipboard chords keep their explicit
client-side paste policy, while Shift+Enter and Alt+Shift+bracket already have
their own terminal routes. Keeping all four pane directions explicit also
protects Linux and Windows from VS Code's global Ctrl+J panel action and Ctrl+K
chord prefix. This keeps workbench shortcuts intact outside terminal focus
without making tmux depend on the Neovim sensor.
Local tmux window cycling does not need the adapter. Bubbling past a one-window
tmux session to another VS Code terminal tab still does: without that command
bridge the outer request fails closed instead of rerouting the chord to editor
tabs.

On macOS, Karabiner remains the only modifier-remapping layer. The macOS VS
Code bindings route the Cmd chord that Karabiner already produced. Terminal
controls that shells and tmux must always receive (`Ctrl-A/B/L/N/R/U/W/Z`) are
sent under `terminalFocus` without depending on Termnav. In particular,
physical `Ctrl-B` reaches tmux as C0 byte `0x02`, while VS Code's normal
`Cmd-B` sidebar command remains active outside the terminal. Other translated
VSCode-style chords override the host only while `termnav.nvimFocused` is true.
Karabiner transports physical `Ctrl-Shift-V` through otherwise-unused `F20`;
focused Neovim receives the distinct CSI-u chord, while terminal and editor
fallbacks retain normal paste behavior without consuming native
`Shift-Cmd-V`. Ctrl+Arrow stays raw in stable, Insiders, Cursor, FB, and
VSCodium builds under the shared Karabiner exemptions and uses the common
bindings. Shift+PageUp/Down similarly override terminal viewport scrolling only
while focused Neovim owns the pane.
