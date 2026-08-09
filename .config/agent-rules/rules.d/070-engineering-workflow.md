# Engineering Workflow

<!-- agent-rule-id: global-engineering-workflow -->

- Always verify changes compile and pass tests before presenting as done.
- Before the first repository-modifying action, read
  `~/.config/agent-rules/playbooks.d/git/worktrees.md`, follow it, and establish
  the correct isolated checkout or worktree, so concurrent agents do not
  collide. Read-only inspection may happen in the current checkout, but edits,
  generation, formatting, staging, commits, and other state-changing actions
  must happen only after that boundary is established. If the current checkout
  is already an appropriate linked worktree, continue there; otherwise create
  or select one first.
- Before presenting non-trivial work as complete, read
  `~/.config/agent-rules/playbooks.d/review/fresh-eyes.md` and perform the
  risk-scaled review it requires.
- You have standing authorization to dispatch subagents; no per-task approval
  is needed. Use them for fresh-eyes review, for independent work that can run
  in parallel, and for wide searches whose intermediate output would otherwise
  crowd the main session. Give each one a concrete brief and, for reviews, its
  own distinct axis. Treat what they report as evidence to verify, not as
  truth. Keep work in the main session when it depends on in-flight context a
  subagent would have to rediscover, is a single short step, or must not run
  concurrently with other edits.
- For implementation and refactoring work, prefer small cycles of
  code/test/review/fix so correctness, maintainability, and regressions are
  checked continuously instead of only at the end.
- When a repo uses `checkrun`, use `checkrun format` and `checkrun lint` for
  local formatting and lint verification, matching the commit hook behavior.
- Always update .h and .cpp files consistently when changing interfaces.
- Read and understand existing code, ownership, and conventions before
  proposing changes, and match the patterns already in the file. Ask when
  unresolved ambiguity about which architectural layer owns a responsibility
  would materially change behavior, interfaces, or the proposed architecture.
- When asked to scrub for updates, search code, docs, tests, config, CI, hooks,
  and generated-facing references, not just source files.
- Don't over-engineer. Solve what's asked, nothing more.
- On entering a directory or repo by any means, read its `AGENTS.md` if present.
