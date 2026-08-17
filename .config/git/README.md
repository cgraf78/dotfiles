# Git Config

This directory owns machine-wide Git policy for this dotfiles checkout:

- `config` is the global Git config. The dotfiles Git merge hook ensures Git
  loads it even on hosts whose existing `~/.gitconfig` suppresses XDG discovery.
- `attributes` defines repository-neutral working-tree normalization.
- `ignore` is the global ignore file referenced by `core.excludesFile`.

## Boundaries

Keep global Git behavior here when it should apply to every checkout on the
machine. Personal identity belongs in `~/.config/git/config-personal`; work
identity, remotes, or aliases belong in `~/.config/git/config-work`; dev-server
overrides belong in `~/.config/git/config-devserver`. `config` includes those
files when present, ordered from broad personal defaults to narrower overrides.

Git hooks live under
[`~/.local/lib/dot/git-hooks`](../../.local/lib/dot/git-hooks/README.md).
They are executable dotfiles-owned policy, so they belong in the dot runtime
library rather than XDG's architecture-independent data directory. They remain
a sibling of `core/` because Git invokes them directly; they are not part of
the `dot` command runtime.

The PATH-visible [`git`](../../.local/bin/README.md) launcher is separate from
this config. It routes `$HOME` and non-repo descendants to the base bare
dotfiles repo, while this directory configures Git once the target repo has
already been selected.
