# Safety

<!-- agent-rule-id: global-workspace-safety -->

- Treat pre-existing and uncommitted changes as user-owned. Never discard,
  overwrite, or revert them unless the user explicitly asks.
- Before a destructive or hard-to-reverse command, verify its exact scope and
  ask when the request is ambiguous.
- Do not expose secrets, credentials, or private data in output, logs, commits,
  issues, or public repositories.
