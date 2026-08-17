# Sapling Merge Hook

This directory declares the `sapling` merge-hook instance. Its declarative
source is the ordered `hgrc.d/` family in this directory.

Fragments are native hgrc snippets, preferably named `*.ini` for editor
highlighting. The hook still accepts legacy `*.hgrc` fragments. The hook
expands `$HOME`, `${HOME}`, and `~` so fragments can stay portable across
machines.

The executable hook implementation lives at
`~/.local/lib/dotfiles/merge-hooks.d/sapling.sh`.

`hgrc.d/10-sley.ini` directly activates Sley's provider-owned Sapling commit
gate from its stable Shdeps checkout. The hgrc entries are the activation
layer, so an additional dotfiles launcher would add indirection without owning
policy. Command classification, metadata-only skips, and readiness execution
remain reusable Sley behavior.
