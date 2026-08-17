# Dotfiles

<!-- agent-rule-id: global-dotfiles-management -->

Base bare repo at `~/.dotfiles`, plus overlay repos discovered from
`~/.config/dot/overlays.d/*.conf`. See `~/.local/share/doc/dotfiles/dot.md`
for full documentation.

- Use the PATH-visible `git` launcher for base dotfiles when you are in
  `$HOME` or a non-repo descendant. Use `git -C ~/.dotfiles-<name>` for overlay
  repos.
- `dot update/push/pull/status/diff/fetch/doctor` operate on base + all
  active overlays. `pull` is an alias for `update`.
- When moving tracked base dotfiles, use `git mv` to preserve history.
- Run base dotfile `git` commands from the path you mean to scope. The launcher
  uses `$HOME` as the work tree outside normal repos, so Git resolves pathspecs
  relative to your current directory.
- The base repo does not track every file under `$HOME`. Check
  `git ls-files -- <path>` or `git status --short -- <path>` before assuming a
  file is tracked.
