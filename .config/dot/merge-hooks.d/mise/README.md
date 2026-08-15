# Mise Merge Hook

This directory declares the `mise` merge-hook instance. It has no declarative
source fragments: the hook synchronizes the tracked global mise config and lock
file by running `mise install` during `dot update`.

The executable hook implementation lives at
`~/.local/lib/dotfiles/merge-hooks.d/mise.sh`.
