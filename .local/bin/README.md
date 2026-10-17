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
- `browser-open` is `$BROWSER` on Linux hosts without a display, outside WSL
  and Termux (set in `env.d/70-platform.sh`, except in VS Code's integrated
  terminal). It opens `http`, `https`, and `mailto` links on the desktop
  running the terminal through `termnav open-url`. When that fails, it uses
  VS Code's opener if a live VS Code window owns the session and the tmux
  server was started from a VS Code terminal (its `bin/remote-cli` is on
  `PATH`); otherwise it shows the URL in a tmux message and on stderr. A URL
  on this host's loopback, such as a dev server or a sign-in that redirects
  to `localhost:PORT`, tries VS Code first because VS Code forwards the port;
  through termnav the message names the port to forward. Device-code
  sign-ins work unchanged. mosh drops the request silently.
- `dot-worktree-gc` deletes proven-merged branches and removes old worktrees
  across every managed clone, driving `git cleanup-repo` from git-tools; its
  implementation lives in `~/.local/lib/dotfiles/worktree-gc.sh`.

The `dot` command itself is not tracked here: Shdeps installs the standalone
Dot release and links its entry point into `~/.local/bin`.

Editor launchers and development commands are contributed by their owning
overlays or Shdeps repositories. Runtime-installed Shdeps links may also appear
in `~/.local/bin`, but they are not tracked here.
