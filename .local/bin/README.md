# Base Local Commands

This directory contains thin, always-active command entry points. Reusable
implementation belongs in its owning repository or under
`~/.local/lib/dotfiles`.

- `dot` enters the standalone locked Dot runtime.
- `git` routes paths in the home-backed client repository to its Git directory
  and passes ordinary repositories to system Git. Git is present in `base` for
  repository synchronization; global Git workflow configuration belongs to the
  `dev` profile.
- `clip` provides the base clipboard-history front door.
- `shell-time` profiles Bash or Zsh startup.
- `ripgrep-link-host` adapts ripgrep's zero-argument hostname interface to the
  explicit `termnav link-host` command during the staged cutover.

Editor launchers and development commands are contributed by their owning
overlays or Shdeps repositories. Runtime-installed Shdeps links may also appear
in `~/.local/bin`, but they are not tracked here.
