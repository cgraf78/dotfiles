# Neovim Config

This directory owns editor configuration. Repo policy should stay behind the
shared `sley` and schema APIs so Neovim, hooks, and command-line tools do not
drift.

## Layout

- `init.lua` is the entry point.
- [`lua/config/`](lua/config/README.md) owns local policy, helper modules, and
  setup routines consumed by LazyVim entry points or plugin specs. These
  modules answer local questions such as "what is a workspace here?" or "how
  should diagnostics look?"
- [`lua/plugins/`](lua/plugins/README.md) owns Lazy plugin specs: plugin
  declarations, dependency options, and key/command surfaces that wire plugins
  into the editor.
- `lazyvim.json` and `lazy-lock.json` are LazyVim state.
- `selene.toml` and `vim.yml` are editor-config lint inputs.

## Keymaps

- `lua/config/keymaps.lua` owns global editor keymaps.
- [`lua/config/keymaps/<domain>.lua`](lua/config/keymaps/README.md) owns
  integration keymaps that need setup timing or domain-specific policy.
- Large keymap domains may keep the `<domain>.lua` entry point and place
  focused helper modules under `lua/config/keymaps/<domain>/`, such as the
  [VSCode-style keymap helpers](lua/config/keymaps/vscode/README.md).
- `lua/plugins/*.lua` may declare plugin-local Lazy `keys = { ... }` entries.
  Avoid raw `vim.keymap.set` calls there; plugin specs should only bridge to a
  config keymap module when lifecycle ordering matters.
- Ctrl-h/j/k/l, local Ctrl-backslash previous-pane selection, Ctrl-Tab,
  Ctrl-Shift-Tab, and Alt-Shift-bracket navigation are provided by Termnav.
  Dotfiles supplies only Bufferline's count/select/move callbacks; nesting,
  tmux clients, SSH relays, and terminal endpoints remain dependency-owned.

## Shared Policy Surfaces

- Workspace roots, session lifecycle/aliases, neo-tree roots, file pickers,
  shell fallback navigation, and lazygit launching live in
  `cgraf78/nvim-workspace`.
- HOME shell navigation globs in `lua/config/nvim-workspace.lua` mirror the
  VS Code HOME workspace policy documented in `~/.vscode/README.md`.
- Formatting routes through `sley hook format-file`.
- Diagnostics route through `sley hook lint-file --json`.
- Language capabilities and JSON/YAML/TOML schema associations are generated
  by `checkrun editor-metadata --json` into
  `checkrun-editor-metadata.json`. Checkrun's reusable Neovim adapter validates
  and materializes that portable contract in Lua, so startup never waits for
  Checkrun or Python. The local `checkrun-nvim.lua` shim supplies only the
  checked projection path and a Shdeps asset resolver.

Keeping these paths shared means Neovim gets the same behavior as `autolint`,
agent hooks, Git hooks, and Sapling hooks.

## Tests

`~/.local/lib/dotfiles/tests/nvim-test` checks the Neovim config and its shared
policy integrations.
