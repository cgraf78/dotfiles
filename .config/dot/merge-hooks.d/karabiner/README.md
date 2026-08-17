# Karabiner Merge Hook

This directory declares the `karabiner` merge-hook instance. Its declarative
source is the ordered `profiles.d/` family in this directory. Each JSON file
uses the native Karabiner top-level shape with a `profiles` array.

The executable hook implementation lives at
`~/.local/lib/dot/core/merge-hooks/karabiner.sh`.
