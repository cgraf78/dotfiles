# Git and GitHub

<!-- agent-rule-id: global-git-github-workflow -->

- Use `gh` for all GitHub operations (PRs, issues, releases).
- For new work, always fetch and base branches from the latest `origin/main`,
  not a stale local `main` or another feature branch.
- Create new PRs for unrelated or independent changes instead of bundling them
  into an in-flight PR.
- Before pushing a branch to GitHub or creating, updating, landing, or cleaning
  up a GitHub pull request, read
  `~/.config/agent-rules/playbooks.d/git/github-pr-lifecycle.md` and follow its
  explicit push, remote verification, and post-merge workflow.
