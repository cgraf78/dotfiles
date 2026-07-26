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
  targets.
- `local-extensions.d/` declares local extension directories that should be
  symlinked into active variants.

The executable hook implementation lives at
`~/.local/lib/dot/core/merge-hooks/vscode.sh`.
