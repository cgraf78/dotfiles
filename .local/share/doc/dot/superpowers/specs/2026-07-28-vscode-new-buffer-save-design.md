# VS Code-style new-buffer save design

## Background

The Neovim configuration already centralizes its VS Code-compatible editor
shortcuts in `.config/nvim/lua/config/keymaps/vscode.lua`. Its current
`Ctrl-S` mapping silently runs `:write`, which fails for an unnamed buffer
because Neovim has no path to write. `Ctrl-N` has no mapping. The
`nvim-workspace` plugin owns workspace roots, pickers, and session persistence;
this editor workflow is local dotfiles policy and does not belong in that
plugin.

## Goals

- Make `Ctrl-N` create a new unnamed, listed buffer in the current window.
- Make `Ctrl-S` save named buffers with the existing write behavior.
- Make `Ctrl-S` on an unnamed buffer prompt for a filename with file
  completion and associate the buffer with the selected path.
- Preserve the editing mode after saving from insert mode.
- Treat cancellation and an empty filename as a no-op.
- Keep all implementation in `vscode.lua`, as requested; a future refactor of
  that module is separate work.

## Non-goals

- No changes to `nvim-workspace`.
- No new Neovim tabpage or split behavior; `Ctrl-N` changes the buffer in the
  current window, matching the existing bufferline-as-editor-tab workflow.
- No changes to other VS Code shortcuts or save automation.
- No overwrite policy beyond Neovim's native `:saveas` handling.

## Design

Add a small local save helper beside the existing Save mappings in
`vscode.lua`.

1. The new-buffer mapping calls `vim.cmd.enew()` in normal mode. Because the
   buffer is created through the normal `:enew` path, it remains a regular
   listed editing buffer and participates in the existing buffer/tab UI.
2. The save helper checks the current buffer name using the structured buffer
   API rather than parsing status text.
3. Named buffers run `:write` as before.
4. Unnamed buffers call `vim.ui.input` with a `file` completion mode. A
   non-empty response is escaped with `vim.fn.fnameescape` and passed to
   `:saveas`, which both writes the file and assigns its name to the buffer.
   Cancelled or empty input returns without changing the buffer.
5. Normal, visual, and select mode mappings call the helper directly. The
   insert-mode mapping exits insert mode, calls the same helper, and re-enters
   insert mode after either the synchronous named-buffer write or the
   asynchronous filename prompt completes.

## Error handling

Neovim's normal command errors remain visible to the user. A cancelled prompt,
empty response, or missing `vim.ui.input` response is a no-op. The helper must
not silently discard a failed `:saveas`, since a failed save should be
actionable and must not look like a successful VS Code save.

## Testing and acceptance

- Add focused checks to the existing Neovim dotfiles test path if its fixture
  can exercise keymaps; otherwise use a headless Neovim fixture that loads the
  keymap module with a minimal `vim.ui.input` stub.
- Verify `<C-n>` produces a new unnamed buffer in the same window.
- Verify `<C-s>` writes a named buffer.
- Verify `<C-s>` prompts for an unnamed buffer, saves to the supplied path, and
  leaves the buffer associated with that path.
- Verify cancellation and empty input leave an unnamed buffer unchanged.
- Verify insert-mode save returns to insert mode for both named and unnamed
  buffers.
- Run the relevant Neovim test and the complete `./.local/bin/dot-test` suite.
- Perform fresh-eyes review of the diff and inspect the final mapping behavior
  before presenting the change as complete.
