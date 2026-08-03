# VS Code Merge Hook Instance

This directory declares the `vscode` merge-hook instance. VS Code declarative
source families and private helpers live in this directory.

- `settings.d/` layers VS Code `settings.json` fragments.
- `keybindings/` layers shared and platform-specific `keybindings.jsonc`
  fragments.
- `extensions.d/` declares marketplace extension bundles and install profiles.
  The default managed-extension manifest lives in a `.replace` group so an
  overlay can replace the whole managed-extension policy with an empty
  manifest.
- `variants.d/` declares VS Code, VS Code Insiders, Cursor, and remote variant
  targets. Darwin rows also carry each application's concrete bundle ID and
  executable path relative to its app bundle. Those identities belong beside
  the target declaration because Karabiner can match either one, and VS Code
  must agree about which application receives a translated chord; tests use
  the same fields to catch a newly supported editor that the keyboard layer
  forgot. A `-` reserves an otherwise empty options column when later metadata
  is present, rather than turning manifest layout into runtime behavior.
- `local-extensions.d/` declares local extension directories that should be
  symlinked into active variants. The termnav adapter is loaded from shdeps'
  stable `$HOME/.local/share/cgraf78/termnav` dependency root so local,
  remote, and WSL extension hosts share the same window-scoped tab bridge. Its
  versioned source directory must stay aligned with the adapter manifest.
  After first registration, reload or restart each editor window, then relaunch
  its existing terminal or tmux clients so they receive the adapter socket.
  Relaunch those clients again after a later editor or extension-host restart.

The executable hook implementation lives at
`~/.local/lib/dot/core/merge-hooks/vscode.sh`.
