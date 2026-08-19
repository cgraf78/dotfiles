# Dotfiles Documentation

This directory contains human-facing documentation owned by the dotfiles
client that is broader than a single config directory. The base repository and
optional overlays publish distinct files into this shared namespace.

- [`dotfiles.md`](dotfiles.md) is the main operating guide for initialization,
  updating, overlays, recovery, and common workflows.
- `superpowers/` contains retained implementation plans and design records that
  are useful as dotfiles context but are not installed into a native app config
  directory. Keeping them here avoids a second top-level documentation tree.
- Optional overlays may add sibling documents or their own subtrees. The base
  client intentionally leaves those names unowned so composed installations do
  not collide.

Prefer colocated README files beside implementation or config when the guidance
only applies to that directory. Use this directory for cross-cutting guides,
operational notes, or design records that need more room than a local README.
