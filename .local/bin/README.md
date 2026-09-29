# Base Local Commands

This directory contains thin, always-active command entry points. Reusable
implementation belongs in its owning repository or under
`~/.local/lib/dotfiles`.

- `git` routes paths in the home-backed client repository to its Git directory
  and passes ordinary repositories to system Git. Git is present in `base` for
  repository synchronization; global Git workflow configuration belongs to the
  `dev` profile.
- `clip` provides the base clipboard-history front door.
- `shell-time` profiles Bash or Zsh startup.
- `dot-worktree-gc` removes old worktrees whose branches are proven merged;
  its implementation lives in `~/.local/lib/dotfiles/worktree-gc.sh`.

The `dot` command itself is not tracked here: Shdeps installs the standalone
Dot release and links its entry point into `~/.local/bin`.

Editor launchers and development commands are contributed by their owning
overlays or Shdeps repositories. Runtime-installed Shdeps links may also appear
in `~/.local/bin`, but they are not tracked here.
