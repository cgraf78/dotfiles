# VS Code Merge Hook Instance

This directory declares the `vscode` merge-hook instance. VS Code declarative
source families and private helpers live in this directory.

- `settings.d/` layers VS Code `settings.json` fragments.
- `keybindings/` layers shared and platform-specific `keybindings.jsonc`
  fragments.
- `extensions.d/` declares marketplace extension bundles and install profiles.
  Dot selects the ordered overlay stream, including `.replace` winners, and
  passes those files explicitly to the shdeps-provided `vscode-exts` command.
  The provider owns the manifest model, validation, platform discovery,
  locking, and additive installation. The default managed-extension manifest
  stays in a `.replace` group so an overlay can replace the whole personal
  extension policy with an empty manifest.
  The thin adapter translates Dot's established `DOT_WINDOWS_HOME` and timeout
  controls to provider-native names; explicitly set `VSCODE_EXTS_*` values take
  precedence.
- `variants.d/` declares VS Code, VS Code Insiders, Cursor, and remote variant
  targets.
- `local-extensions.d/` declares local extension directories that should be
  symlinked into active variants. Its third TSV column names comma-separated
  variant options that disable that extension. The Sley adapter is loaded from
  shdeps' stable `$HOME/.local/share/cgraf78/sley` dependency root. Sley owns
  the extension implementation and its detailed behavioral suite; this merge
  hook owns only activation, the `no-sley` opt-out, and a compatibility smoke
  test. Keeping that boundary explicit prevents editor behavior from drifting
  into a second consumer-owned copy while preserving local deployment policy.
  The Termnav adapter uses
  `no-termnav`; opting out unregisters it and prunes identifiable older
  dot-managed symlinked generations even when the configured current payload
  is unavailable. Otherwise the adapter is loaded from shdeps' stable
  `$HOME/.local/share/cgraf78/termnav` dependency root so local, remote, and WSL
  extension hosts share the same window-scoped tab bridge. Its versioned source
  directory must stay aligned with the adapter manifest. The same alignment
  requirement applies to Sley's versioned source directory.
  After first registration, reload or restart each editor window, then relaunch
  its existing terminal or tmux clients so they receive the adapter socket.
  Relaunch those clients again after a later editor or extension-host restart.

The executable hook implementation lives at
`~/.local/lib/dotfiles/merge-hooks.d/vscode.sh`.
