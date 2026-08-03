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
bindings. The shared terminal `Ctrl-Tab` and `Ctrl-Shift-Tab` send-sequence
routes are the exception: they are emitted last so older or more specific local
terminal-tab handlers cannot consume those chords before tmux receives them.
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
effective platform projection (`all.d` plus that platform's family). A removed
or changed active object must enter retirement; retirement is append-only and
must live in `all.d` so every platform can remove a synchronized foreign
generation. After the initial bridge in this PR, a new retirement object must
also appear in the prior active source, preventing the history file from
becoming an unchecked list that could delete local-only bindings. The initial
file is the one exception because it must describe generated output from before
retirement history existed.

Native paths use an atomic rename. WSL uses the existing verified write with
best-effort rollback because Windows can deny replacement of an open VS Code
file. Malformed retirement records fail closed because guessing at ownership
could either delete a local binding or strand a managed one.

Termnav's local VS Code extension publishes `termnav.nvimFocused` only while
the active integrated terminal and, when present, focused tmux pane are owned
by Neovim. `all.d/20-nvim-focus.jsonc` uses that leased context to pass
VSCode-style chords to Neovim; missing or expired context leaves the normal VS
Code command active.
VS Code also treats a context key that was never published as false. Systems
without the Termnav extension therefore follow the same path as systems where
Neovim is not focused: positive Neovim routes stay inactive, negated host
routes stay active, and chords without an explicit host override fall through
to VS Code's normal defaults.

Ctrl+Shift letters use CSI-u so Shift is not collapsed into the corresponding
plain Ctrl byte. The merge test inventories literal `<C-S-letter>` mappings
under Neovim's Lua config and requires each one to have the correctly encoded
focused route. This deliberate development-time coupling prevents a new
VSCode-style Neovim mapping from silently becoming host-owned; satisfying it
normally requires editing only the JSONC source, not the generic merge hook.
The same inventory scans literal Ctrl+single-punctuation mappings. Known
punctuation has explicit terminal and Karabiner vocabulary; a new symbol fails
closed until that cross-layer spelling and sequence are deliberately added.
The exception is a physical chord whose existing Karabiner translation loses
information or collides with a different macOS shortcut. In that case the
keyboard layer must preserve a distinct observed chord as well. Ctrl+Shift+V
is the current example: keeping it raw avoids conflating Neovim's yank history
with macOS Shift+Cmd+V, which VS Code uses for Markdown preview.

On macOS, Karabiner remains the only modifier-remapping layer. The macOS VS
Code bindings merely route the Cmd chord that Karabiner already produced: they
run the ordinary VS Code command outside Neovim and send the corresponding
terminal sequence while `termnav.nvimFocused` is true. For each supported VS
Code application, tests resolve Karabiner's first matching structured
manipulator and require the generated keybindings to route the chord it
actually emits. This models app conditions and rule order rather than
duplicating a list of today's translated keys. Ctrl+Arrow and the deliberately
distinct Ctrl+Shift+V stay raw and use common bindings. The supported
applications and their concrete bundle/executable identities come from the
variant manifest, so adding an editor cannot silently omit it from this
cross-layer proof.

This ownership policy applies when an integrated terminal has focus: Neovim
gets the chord when it owns the active pane, and the VS Code workbench gets it
otherwise. It does not redefine Windows-style shortcuts for ordinary macOS
editor focus; those remain the responsibility of the existing Karabiner
profile and VS Code defaults. The narrow Ctrl+Shift+V editor binding preserves
the historical paste behavior after Karabiner stopped translating that
physical chord; it is compatibility glue for the raw-chord exception above,
not a second general editor-shortcut policy.
