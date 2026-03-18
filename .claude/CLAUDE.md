@~/.claude/CLAUDE-shared.md

# Personal Rules

## Workflow

- For new work, always fetch and base branches from the latest `origin/main`, not a stale local `main` or another feature branch.
- Create new PRs for unrelated or independent changes instead of bundling them into an in-flight PR.
- Write PR descriptions so they also work well as squash-merge commit bodies: lead with a concise summary of what changed and why.
- Keep in-flight PR branches current with the latest `origin/main`; if `origin/main` has moved and I'm touching the branch again, rebase it and update the PR.
- Before saying a PR was updated, verify that the PR is still open; if it was already merged or closed, create a new branch/PR instead of assuming more branch pushes update the old PR.
