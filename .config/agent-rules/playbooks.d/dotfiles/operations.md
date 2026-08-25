# Dotfiles Operations

<!-- agent-rule-id: dotfiles-operations -->
<!-- agent-rule-trigger: Operating or modifying the base dotfiles repository, an overlay, the dot client, or generated dotfiles state -->

The base client uses `~/.dotfiles` as a separate Git directory with `$HOME` as
its worktree. Active overlays are discovered from
`~/.config/dot/overlays.d/*.conf` and use ordinary repository worktrees.

## Select the correct repository

- Use the PATH-visible `git` launcher for base dotfiles from `$HOME` or a
  non-repository descendant. Use `git -C ~/.dotfiles-<name>` for an overlay.
- Run base Git commands from the path whose pathspec scope you intend. Outside
  another repository, the launcher uses `$HOME` as the worktree, so relative
  pathspecs follow the current directory.
- The base repository does not track every file under `$HOME`. Check
  `git ls-files -- <path>` or `git status --short -- <path>` before assuming a
  file belongs to it.
- When moving a tracked base file, use `git mv` so history and index state remain
  clear.

## Operate the client

- `dot update`, `push`, `pull`, `status`, `diff`, `fetch`, and `doctor` operate
  on the base repository plus active overlays. `pull` aliases `update`.
- The public `cgraf78.github.io/d` shortcut delegates to standalone Dot;
  `dot init` owns client repository initialization and recovery.
- Fresh base clients use `core.bare=false` with an explicit `core.worktree`;
  legacy bare clients remain supported.

## Verify installed state

- Test changes from the source checkout before installation.
- After related provider and consumer changes have landed, run `dot update -f`
  so every overlay and generated target is rebuilt from the landed revisions.
- Verify the generated target or installed link, not only the source file, and
  finish with the full `dot test` suite required by repository policy.
