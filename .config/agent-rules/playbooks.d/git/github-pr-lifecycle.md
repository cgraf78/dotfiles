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
- If `origin/main` has moved and the branch is being touched again, determine
  whether the repository requires an up-to-date branch and whether the change is
  affected before rebasing. Rerun checks affected by a new base.

## Commit and push safely

- Follow the repository's commit and pull-request template.
- Perform privacy, secret, and repository-boundary reviews silently. Mention
  them in the pull-request description only when a result or constraint is
  material to reviewers.
- Amend an unpushed commit instead of stacking a corrective commit. Before an
  amend, fixup, or rebase, verify the commit is unpushed with
  `git log --oneline origin/main..HEAD` or an equivalent comparison.
- Do not assume the intended commit is `HEAD`. When uncommitted changes belong
  to multiple existing commits, leave them unstaged and use an appropriate
  history-aware routing tool such as `git absorb-and-rebase`.
- Before rewriting a published pull-request branch, verify the pull request is
  open, record the expected old remote head, and follow repository policy for
  history updates. When a rewrite is authorized, push the explicit destination
  with `--force-with-lease=<destination>:<expected-old-oid>` and then verify both
  the remote branch and pull-request head. Never use an unrestricted force push.
- Name the remote, source commit, and full destination explicitly:
  `git push <remote> <source>:refs/heads/<destination>`. Do not rely on inherited
  upstream configuration for feature-branch publication.
- After pushing, verify that the destination branch resolves to the intended
  commit and that the pull request head matches it.

## Format the pull request

- Write the description so it can serve as the squash-merge commit body.
- Use `## Summary` and `## Testing` unless the repository template specifies a
  different structure.
- Begin `## Summary` with a short paragraph explaining what changed and why.
  Follow it with compact bullets for behavior, scope, and material constraints
  when those details help reviewers scan the change.
- Under `## Testing`, list the exact commands or checks and their relevant
  outcomes. Distinguish passing checks from skips, unavailable checks, and a
  pull request with no GitHub check contexts.
- Add `## Review` only when fresh-eyes or specialist review occurred. Name the
  review axes and material findings addressed instead of offering generic
  praise.
- Leave a blank line after each heading and between sections, and separate
  paragraphs and lists with a blank line. Avoid compressed Markdown that makes
  sections run together.
- Add sections such as rollout, risks, dependencies, or breaking changes only
  when they are material. Omit empty boilerplate and keep secrets or
  inappropriate private detail out of public repositories.

## Land and clean up

- Monitor required checks and review feedback. Enable auto-merge only when it
  is part of the repository's established policy and the requested work includes
  landing.
- After merge, remove the completed worktree together with its merged local
  branch, using the host's landing or cleanup tooling scoped to that one
  worktree (an on-demand playbook names it when it is installed), with the
  shell's working directory outside the worktree: cleanup that checks for
  processes using a worktree keeps one a shell is parked in. Without such
  tooling, first run `git -C <path> status --ignored --short`: if it lists
  anything, keep the worktree and report what it holds, since
  `git worktree remove` silently deletes ignored files (a local `.env`, say).
  Otherwise run `git worktree remove <path>` (never `--force`) from outside
  the worktree, then `git branch -d <branch>`, which refuses an unmerged
  branch; if it refuses (after a squash or rebase landing, say), leave the
  branch and report it. Never run an unscoped worktree removal: it would also
  remove other clean worktrees, including ones concurrent agents just
  created.
- Do not treat a successful local push, stale pull-request page, or queued CI as
  proof that the requested remote state has been reached; query the authoritative
  remote state before reporting completion.
- Pass an explicit repository to `gh` when the current directory may belong to
  another checkout. Distinguish absent checks, queued checks, a selector job
  that never acquired a runner or steps, and a test job that actually failed.
- If a landing command fails, query pull-request state before retrying. The
  remote merge may have completed before local synchronization or cleanup
  failed.
- Delete merged local branches only with tooling that proves squash, rebase,
  and stacked landings exactly, or with `git branch -d`. Do not force-delete
  with `git branch -D` on the strength of a tree comparison or a merged pull
  request page.
