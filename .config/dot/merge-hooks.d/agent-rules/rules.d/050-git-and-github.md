# Git and GitHub

<!-- agent-rule-id: global-git-github-workflow -->

- Use `gh` for all GitHub operations (PRs, issues, releases).
- For repo-modifying work, load the worktree playbook before making changes so
  concurrent agents do not collide in the same checkout.
- For new work, always fetch and base branches from the latest `origin/main`,
  not a stale local `main` or another feature branch.
- Create new PRs for unrelated or independent changes instead of bundling them
  into an in-flight PR.
- Write PR descriptions so they also work well as squash-merge commit bodies:
  lead with a concise summary of what changed and why.
- Keep in-flight PR branches current with the latest `origin/main`; if
  `origin/main` has moved and I'm touching the branch again, rebase it and
  update the PR.
- After merging a PR, update local `main` from `origin/main`, verify status, and
  delete the completed local feature branch when it is no longer needed.
- Before saying a PR was updated, verify that the PR is still open; if it was
  already merged or closed, create a new branch/PR instead of assuming more
  branch pushes update the old PR.
- For a branch push, verify the remote URL and intended source commit. Name the
  remote and full destination explicitly with
  `git push <remote> <source>:refs/heads/<destination>` instead of relying on an
  implicit push destination.
- After pushing a branch, verify the remote destination resolves to the intended
  commit and, when applicable, the pull request head matches it. Use the
  appropriate workflow instead for tags or review-system refs.
- When fixing an unpushed commit, amend it instead of creating a new commit.
  Never amend already-pushed commits. ALWAYS check
  `git log --oneline origin/main..HEAD` (or equivalent) before any amend, fixup,
  or rebase to confirm the target commit is unpushed. Don't assume the target
  commit is HEAD — for non-HEAD commits, leave changes unstaged and run
  `git absorb-and-rebase` to auto-route hunks to the correct commits.
