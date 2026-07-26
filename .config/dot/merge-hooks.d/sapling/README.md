# Sapling Merge Hook

This directory declares the `sapling` merge-hook instance. Its declarative
source is the ordered `hgrc.d/` family in this directory.

Fragments are native hgrc snippets, preferably named `*.ini` for editor
highlighting. The hook still accepts legacy `*.hgrc` fragments. The hook
expands `$HOME`, `${HOME}`, and `~` so fragments can stay portable across
machines.

The executable hook implementation lives at
`~/.local/lib/dot/core/merge-hooks/sapling.sh`.
