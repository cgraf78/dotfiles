# Engineering Workflow

<!-- agent-rule-id: global-engineering-workflow -->

- Always verify changes compile and pass tests before presenting as done.
- Before the first repository-modifying action, read
  `~/.config/dot/agent-playbooks.d/git/worktrees.md` and follow it.
- Before the first repository-modifying action, establish the correct isolated
  checkout or worktree. Read-only inspection may happen in the current
  checkout, but edits, generation, formatting, staging, commits, and other
  state-changing actions must happen only after that boundary is established.
  If the current checkout is already an appropriate linked worktree, continue
  there; otherwise create or select one first.
- Before presenting non-trivial work as complete, read
  `~/.config/dot/agent-playbooks.d/review/fresh-eyes.md` and perform the
  risk-scaled review it requires.
- For implementation and refactoring work, prefer small cycles of
  code/test/review/fix so correctness, maintainability, and regressions are
  checked continuously instead of only at the end.
- When a repo uses `checkrun`, use `checkrun format` and `checkrun lint` for
  local formatting and lint verification, matching the commit hook behavior.
- Always update .h and .cpp files consistently when changing interfaces.
- Read and understand existing code before proposing changes. Match existing
  patterns in the file.
- When asked to scrub for updates, search code, docs, tests, config, CI, hooks,
  and generated-facing references, not just source files.
- Inspect existing ownership and conventions first. Ask when unresolved
  ambiguity about which architectural layer owns a responsibility would
  materially change behavior, interfaces, or the proposed architecture.
- Don't over-engineer. Solve what's asked, nothing more.
- When navigating into a directory or repo (whether via cd or any other means),
  check for `AGENTS.md` in that directory and read it if present.
