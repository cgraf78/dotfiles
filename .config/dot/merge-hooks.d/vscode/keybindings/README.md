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

Termnav's local VS Code extension publishes `termnav.nvimFocused` only while
the active integrated terminal and, when present, focused tmux pane are owned
by Neovim. `all.d/20-nvim-focus.jsonc` uses that leased context to pass
VSCode-style chords to Neovim; missing or expired context leaves the normal VS
Code command active.

On macOS, Karabiner remains the only modifier-remapping layer. The macOS VS
Code bindings merely route the Cmd chord that Karabiner already produced: they
run the ordinary VS Code command outside Neovim and send the corresponding
terminal sequence while `termnav.nvimFocused` is true. Ctrl+Arrow stays raw in
VS Code under the existing Karabiner exemptions and uses the common bindings.
