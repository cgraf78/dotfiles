# VS Code Keybindings

This directory groups VS Code keybinding source families by platform.

- `all.d/` applies to every VS Code config target.
- `linux.d/` applies on native Linux.
- `macos.d/` applies on macOS.
- `windows.d/` applies on Windows and WSL-backed Windows VS Code targets.

Each directory is a merge-hook family. Direct `*.jsonc` files aggregate in
lexical order, and an immediate `.replace/` group contributes only its last
matching `*.jsonc` file.

## Adding Or Changing A Binding

Use this decision order:

1. If VS Code and xterm already deliver the desired key in every relevant
   client, add nothing. A Neovim mapping alone is not a reason to manage a VS
   Code binding.
2. If a default workbench command captures a key that xterm encodes natively,
   remove that command from `terminal.integrated.commandsToSkipShell` rather
   than adding a send-sequence route. `Ctrl-J` requires this path because VS
   Code's `sendSequence` command normalizes its LF byte to CR. The settings
   merge preserves unrelated local and Settings Sync entries; for a command
   managed here, the managed positive or negative form wins by command ID.
3. If the terminal owns the chord whenever it is focused, add the common route
   to `all.d/10-keybindings.jsonc` with plain `terminalFocus`. This includes
   terminal protocol normalization and explicit decisions that tmux/shell
   behavior outranks a workbench shortcut.
4. If overriding normal VS Code behavior is valid only while Neovim owns the
   active pane, add it to `all.d/20-nvim-focus.jsonc` with exactly
   `terminalFocus && termnav.nvimFocused`.
5. If the VS Code client owns a behavior such as copy, paste, quick-open, or
   terminal toggle, define the disjoint client and terminal conditions in
   `all.d/10-keybindings.jsonc`; do not infer Neovim from a missing context key.
6. Add a platform entry only when the platform changes the physical chord or
   desired client behavior. In particular, `macos.d/10-keybindings.jsonc`
   translates Karabiner's output but mirrors the ownership decision from steps
   3-5; it does not create a separate macOS focus policy. See the physical-key
   ownership policy below before adding a macOS-only transport.
7. Encode Ctrl letters and exact C0 controls as their byte. For a modified key
   with no exact C0 identity, use CSI-u: `ESC [ <ASCII> ; <modifier> u`. Ctrl is
   5 and Ctrl+Shift is 6. Legacy terminals encode physical Ctrl+/ as Ctrl-_
   (`0x1f`), so Neovim intentionally maps both spellings.
8. When changing or deleting an existing managed object, copy the complete old
   object into `all.d/00-retirements.jsonc` and add `dotfiles.retire: true`.
   Never place active policy in that file.
9. Extend `core-merges` for Linux, macOS, and Windows with and without Termnav,
   seed any stale generation that must be removed, and add a Neovim keymap test
   when terminal encoding aliases or CSI-u identity matter.

Existing local-only bindings keep their normal precedence over managed
bindings. The terminal-native `Ctrl-Tab` and `Ctrl-Shift-Tab` send-sequence
routes are the exception: they are emitted last so an overlapping local handler
cannot consume those chords before the pty. They depend only on `terminalFocus`,
not on the Termnav adapter; native VS Code editor switching remains in control
outside the terminal.

## macOS Physical-Key Ownership

Karabiner is the single physical-remapping layer on macOS. VS Code keybindings
may interpret the stable key that Karabiner produced according to application
context, but they must not introduce a second scan-code or modifier-remapping
scheme. This boundary keeps hardware and keyboard-layout normalization in one
place while leaving `terminalFocus`, `editorFocus`, and Neovim ownership with
the application that can actually observe them.

Use a private function-key transport only when a physical chord cannot reach VS
Code reliably across supported macOS layouts or clients. Scope the Karabiner
rule to the complete, explicit VS Code bundle inventory; never include WezTerm
or generic terminal applications merely for consistency. The matching macOS VS
Code bindings must document every context that consumes the transport, while
unlisted contexts deliberately receive no action. Tests must prove that the
function keys have no other Karabiner producer or VS Code consumer.

The reserved transport inventory is:

- `F16` through `F19`: physical Alt-Shift-H/J/K/L, respectively. A focused
  terminal receives `ESC H/J/K/L` for Termnav pane movement, while a focused
  editor moves its active editor group in the same direction.
- `F20`: physical Ctrl-Shift-V. Focused Neovim receives its distinct CSI-u
  identity, while terminal and editor contexts preserve paste behavior.

These are private integration keys rather than user-facing shortcuts. A
physical extended-keyboard F16-F20 press is therefore intentionally equivalent
to the corresponding synthesized transport while a supported VS Code client is
frontmost.
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
tmux prefix, explicit `Ctrl-H/K/L` directional pane controls, `Ctrl-\` for the
local previous pane, native `Ctrl-J` passthrough, both `Ctrl-Tab` directions for
layered tab navigation, and Ctrl+/ normalization to the conventional Ctrl-_
byte. Clipboard chords keep their explicit
client-side paste policy, while Shift+Enter and Alt+Shift+bracket already have
their own terminal routes. Removing `workbench.action.togglePanel` from the
terminal skip-shell set protects native Ctrl-J from VS Code's global panel
shortcut without passing LF through `sendSequence`'s CR normalization. The
explicit Ctrl-K route still protects against VS Code's chord prefix. Workbench
shortcuts remain intact outside terminal focus, including VS Code's native
Ctrl-backslash split-editor action. Terminal transport does not depend on the
Neovim sensor. On macOS, Karabiner leaves the punctuation chord as Ctrl-\ while
its terminal exclusions leave WezTerm controls raw, so the common binding also
covers VS Code on macOS without a second translated route. VS Code's terminal
handler continues to retain Meta-key workbench commands, so Cmd-J still toggles
the panel while raw Ctrl-J reaches xterm.
Local tmux window cycling does not need the adapter. Bubbling past a one-window
tmux session to another VS Code terminal tab still does: without that command
bridge the outer request fails closed instead of rerouting the chord to editor
tabs.

On macOS, Karabiner remains the only modifier-remapping layer. The macOS VS
Code bindings route the Cmd chord that Karabiner already produced, while using
the same ownership classification as common policy. Terminal controls that
shells and tmux must always receive (`Ctrl-A/B/L/N/R/U/W/Z` and `Ctrl-/`) are
sent under `terminalFocus` without depending on Termnav. In particular,
physical `Ctrl-B` reaches tmux as C0 byte `0x02`, physical `Ctrl-/` reaches the
pty as `0x1f`, and the corresponding native Cmd shortcuts remain active outside
the terminal. Other translated VSCode-style chords override the host only while
`termnav.nvimFocused` is true.
Karabiner transports physical `Ctrl-Shift-V` through otherwise-unused `F20`;
focused Neovim receives the distinct CSI-u chord, while terminal and editor
fallbacks retain normal paste behavior without consuming native
`Shift-Cmd-V`. Ctrl+Arrow stays raw in stable, Insiders, Cursor, FB, and
VSCodium builds under the shared Karabiner exemptions and uses the common
bindings. Shift+PageUp/Down similarly override terminal viewport scrolling only
while focused Neovim owns the pane.
