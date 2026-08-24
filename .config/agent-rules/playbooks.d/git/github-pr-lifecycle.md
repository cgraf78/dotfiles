# GitHub Branch and Pull Request Lifecycle

<!-- agent-rule-id: git-github-pr-lifecycle -->
<!-- agent-rule-trigger: Pushing a branch to GitHub or creating, updating, landing, or cleaning up a GitHub pull request -->

Use the repository's established contribution and CI conventions. Keep one
logical change per pull request and make every local-to-remote transition
explicit and verifiable.

## Prepare the branch

- Confirm the remote URL and default branch. Fetch and base new work on the
  latest `origin/main` unless the task explicitly targets another branch.
- Keep unrelated repositories or concerns in separate branches and pull
  requests.
- Before updating an existing pull request, verify that it is still open. If it
  was merged or closed, create a new branch and pull request instead of assuming
  another push will update it.
- If `origin/main` has moved and the branch is being touched again, rebase it and
  rerun the checks affected by the new base.

## Commit and push safely

- Follow the repository's commit and pull-request template. Write the pull
  request description so it can serve as the squash-merge commit body, leading
  with what changed and why.
- Perform privacy, secret, and repository-boundary reviews silently. Mention
  them in the pull-request description only when a result or constraint is
  material to reviewers.
- Amend an unpushed commit instead of stacking a corrective commit. Before an
  amend, fixup, or rebase, verify the commit is unpushed with
  `git log --oneline origin/main..HEAD` or an equivalent comparison.
- Do not assume the intended commit is `HEAD`. When uncommitted changes belong
  to multiple existing commits, leave them unstaged and use an appropriate
  history-aware routing tool such as `git absorb-and-rebase`.
- Name the remote, source commit, and full destination explicitly:
  `git push <remote> <source>:refs/heads/<destination>`. Do not rely on inherited
  upstream configuration for feature-branch publication.
- After pushing, verify that the destination branch resolves to the intended
  commit and that the pull request head matches it.

## Land and clean up

- Monitor required checks and review feedback. Enable auto-merge only when it
  is part of the repository's established policy and the requested work includes
  landing.
- After merge, update local `main` from `origin/main`, verify the resulting
  status, and release the completed worktree through the environment's managed
  worktree workflow.
- Do not treat a successful local push, stale pull-request page, or queued CI as
  proof that the requested remote state has been reached; query the authoritative
  remote state before reporting completion.
