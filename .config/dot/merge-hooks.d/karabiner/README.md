# Karabiner Merge Hook

This directory declares the `karabiner` merge-hook instance. Its declarative
source is the ordered `profiles.d/` family in this directory. Each JSON file
uses the native Karabiner top-level shape with a `profiles` array.

The executable hook implementation lives at
`~/.local/lib/dotfiles/merge-hooks.d/karabiner.sh`.

The cross-layer policy for macOS physical remapping, VS Code context routing,
and the reserved F16-F20 transport range is documented in the
[`dotfiles-dev` VS Code keybinding guide](https://github.com/cgraf78/dotfiles-dev/blob/main/home/.config/dot/merge-hooks.d/vscode/keybindings/README.md#macos-physical-key-ownership).
