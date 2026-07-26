# GStack Merge Hook

This directory declares the `gstack` merge-hook instance. It has no
declarative source fragments: the hook refreshes lightweight gstack
registrations during `dot update` when gstack is installed.

The executable hook implementation lives at
`~/.local/lib/dot/core/merge-hooks/gstack.sh`.
