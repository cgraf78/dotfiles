# Dotfiles

<!-- agent-rule-id: global-dotfiles-management -->

Base bare repo at `~/.dotfiles`, plus overlay repos discovered from
`~/.config/dot/overlays.d/*.conf`. See `~/.local/share/doc/dot/dot.md`
for full documentation.

- Use the PATH-visible `git` launcher for base dotfiles when you are in
  `$HOME` or a non-repo descendant. Use `git -C ~/.dotfiles-<name>` for overlay
  repos.
- `dot update/push/pull/status/diff/fetch/doctor` operate on base + all
  active overlays. `pull` is an alias for `update`.
- When moving tracked base dotfiles, use `git mv` to preserve history.
- Run base dotfile `git` commands from the path you mean to scope. The launcher
  uses `$HOME` as the work tree outside normal repos, so pathspecs are resolved
  by Git relative to your current directory.
- Dotfiles is a bare repo and does not track every file under `$HOME`. Before
  assuming a file is part of dotfiles, check `git ls-files -- <path>` or
  `git status --short -- <path>`.
