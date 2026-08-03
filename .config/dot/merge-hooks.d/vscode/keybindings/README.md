# VS Code Keybindings

This directory groups VS Code keybinding source families by platform.

- `all.d/` applies to every VS Code config target.
- `termnav.d/` applies only to targets that load the Termnav adapter.
- `linux.d/` applies on native Linux.
- `macos.d/` applies on macOS.
- `windows.d/` applies on Windows and WSL-backed Windows VS Code targets.

Each directory is a merge-hook family. Direct `*.jsonc` files aggregate in
lexical order, and an immediate `.replace/` group contributes only its last
matching `*.jsonc` file.

Existing local-only bindings keep their normal precedence over managed
bindings. On adapter-enabled targets, the terminal `Ctrl-Tab` and
`Ctrl-Shift-Tab` send-sequence routes are the exception: they are emitted last
so older or more specific local terminal-tab handlers cannot consume those
chords before tmux receives them.
`all.d/00-retirements.jsonc` is append-only exact history. Its
`dotfiles.retire` records are source-only and never reach VS Code. The hook
matches those complete objects rather than guessing ownership from a key,
command, or condition, so a similar local binding remains untouched. Keeping
history in source is deliberate: JSONC comments are not merged semantically by
Settings Sync, while every field that is merged can also affect VS Code's
keybinding resolver or command behavior.

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
consume an identical local-only binding. The only exception is the sealed
`dotfiles.retire-proof` generation for PR #90, which reached live profiles while
still under review; the validator fixes both that proof label and its canonical
exact-object set so it cannot become a general bypass.

Native paths use an atomic rename. WSL uses the existing verified write with
best-effort rollback because Windows can deny replacement of an open VS Code
file. Malformed retirement records fail closed because guessing at ownership
could either delete a local binding or strand a managed one.

Termnav's local VS Code extension publishes `termnav.nvimFocused` only while
the active integrated terminal and, when present, focused tmux pane are owned
by Neovim. `all.d/20-nvim-focus.jsonc` uses that leased context to pass
VSCode-style chords to Neovim. The extension is the only process sensor in this
layer: VS Code keybinding conditions cannot inspect the foreground process in a
tmux pane by themselves.

VS Code treats a context key that was never published as false. That is a
missing capability, not evidence that the workbench owns every chord.
Neovim-specific additions must therefore be positive-only
(`terminalFocus && termnav.nvimFocused`). Do not pair them with negated host
commands for chords that normally reach the terminal; such fallbacks steal
keys whenever the adapter is absent. Existing baseline routes such as terminal
paste, quick open, and terminal toggle remain explicit, while other chords use
normal VS Code and xterm.js resolution. A variant that cannot load the adapter
uses `no-termnav`, which unregisters managed adapter generations; the positive
routes then remain inert by construction and the Termnav-only tab family is
omitted. Without the sensor, Neovim-aware routing is unavailable, but normal
editor, workbench, shell, and tmux behavior continues.

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
