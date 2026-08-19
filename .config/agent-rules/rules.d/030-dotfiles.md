# Dotfiles

<!-- agent-rule-id: global-dotfiles-management -->

The base client uses `~/.dotfiles` as a separate Git directory with `$HOME` as
its worktree, plus overlay repos discovered from
`~/.config/dot/overlays.d/*.conf`. Fresh clients set `core.bare=false` and an
explicit `core.worktree`; legacy bare clients remain supported. See
`~/.local/share/doc/dotfiles/dotfiles.md` for full documentation.

- Use the PATH-visible `git` launcher for base dotfiles when you are in
  `$HOME` or a non-repo descendant. Use `git -C ~/.dotfiles-<name>` for overlay
  repos.
- `dot update/push/pull/status/diff/fetch/doctor` operate on base + all
  active overlays. `pull` is an alias for `update`.
- The public `cgraf78.github.io/d` shortcut delegates to standalone Dot;
  `dot init` owns client repository initialization and recovery.
- When moving tracked base dotfiles, use `git mv` to preserve history.
- Run base dotfile `git` commands from the path you mean to scope. The launcher
  uses `$HOME` as the work tree outside normal repos, so Git resolves pathspecs
  relative to your current directory.
- The base repo does not track every file under `$HOME`. Check
  `git ls-files -- <path>` or `git status --short -- <path>` before assuming a
  file is tracked.
