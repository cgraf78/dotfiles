# Git Config

This directory owns machine-wide Git policy for this dotfiles checkout:

- `config` is the global Git config loaded by Git itself.
- `attributes` defines repository-neutral working-tree normalization.
- `ignore` is the global ignore file referenced by `core.excludesFile`.

## Boundaries

Keep global Git behavior here when it should apply to every checkout on the
machine. Personal identity belongs in `~/.config/git/config-personal`; work
identity, remotes, or aliases belong in `~/.config/git/config-work`; dev-server
overrides belong in `~/.config/git/config-devserver`. `config` includes those
files when present, ordered from broad personal defaults to narrower overrides.

Git hooks live under [`~/.local/share/git-hooks`](../../.local/share/git-hooks/README.md)
because Git's `core.hooksPath` expects an executable hook directory, not files
beside the config.

The PATH-visible [`git`](../../.local/bin/README.md) launcher is separate from
this config. It routes `$HOME` and non-repo descendants to the base bare
dotfiles repo, while this directory configures Git once the target repo has
already been selected.
