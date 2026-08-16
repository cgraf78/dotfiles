# Mise Merge Hook

This directory declares the `mise` merge-hook instance. It has no declarative
source fragments: the hook synchronizes the tracked global mise config and lock
file by running `mise install` during `dot update`.

Termux skips this hook because the tracked global toolset targets Linux and
macOS release assets. Android-supported dependencies come from Termux packages
instead.

The executable hook implementation lives at
`~/.local/lib/dotfiles/merge-hooks.d/mise.sh`.
