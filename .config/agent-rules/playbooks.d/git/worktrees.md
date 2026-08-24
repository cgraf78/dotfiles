# Git Worktrees

<!-- agent-rule-id: git-worktree-default -->
<!-- agent-rule-trigger: Modifying a Git repository -->

Use isolated git worktrees by default for implementation, refactoring,
debugging, review-fix, and other repo-modifying work so multiple agents can
work in the same repository without colliding.

- Before modifying a Git repo, check whether the current checkout is already an
  isolated worktree by comparing `git rev-parse --git-dir` and
  `git rev-parse --git-common-dir`; also check
  `git rev-parse --show-superproject-working-tree` so submodules are not
  mistaken for worktrees.
- If already in a linked worktree, continue there. Do not create nested or
  redundant worktrees.
- If the agent runtime provides a native worktree or isolated-workspace
  mechanism, prefer that over manual `git worktree add`.
- Otherwise create a project-local worktree for new repo-modifying work,
  normally under `.worktrees/<branch-name>/`, from the latest `origin/main`
  unless the task explicitly targets another base.
- Before creating a project-local worktree directory, verify `.worktrees/` or
  the chosen worktree directory is ignored. If it is not ignored, use an
  already-ignored or external sibling worktree root. Do not modify ignore policy
  from the non-isolated checkout merely to bootstrap the current task; make a
  desired repository-wide ignore convention its own intentional change from an
  isolated checkout.
- Use descriptive branch names that make concurrent agent work easy to identify.
- Do not create a worktree for read-only inspection, quick command output,
  emergency operational commands, or when the user explicitly asks to work in
  the current checkout.
- If setup or baseline tests are required by the repo, run them inside the
  worktree before making changes and report any pre-existing failures.
- After merge or abandonment, remove completed worktrees with
  `git worktree remove` and prune stale metadata with `git worktree prune` when
  appropriate.
