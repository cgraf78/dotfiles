# Engineering Workflow

<!-- agent-rule-id: global-engineering-workflow -->

- Always verify changes compile and pass tests before presenting as done.
- Before the first repository-modifying action, read
  `~/.config/agent-rules/playbooks.d/git/worktrees.md`, follow it, and
  establish the correct isolated checkout or worktree so concurrent agents do
  not collide. Read-only inspection may use the current checkout; edits,
  generation, formatting, staging, commits, and other state changes must wait
  until that boundary exists. If already in an appropriate linked worktree,
  continue there; otherwise create or select one first.
- Before presenting non-trivial work as complete, read
  `~/.config/agent-rules/playbooks.d/review/fresh-eyes.md` and perform the
  risk-scaled review it requires.
- You have standing authorization to dispatch subagents. Use them for
  fresh-eyes review, independent parallel work, and wide searches whose
  intermediate output would crowd the main session. Give each a concrete brief
  and, for reviews, a distinct axis; treat their reports as evidence to
  verify, not truth. Keep work in the main session when it depends on
  in-flight context a subagent would rediscover, is a single short step, or
  must not run concurrently with other edits.
- For implementation and refactoring, prefer small code/test/review/fix cycles
  so correctness, maintainability, and regressions are checked continuously.
- In repos that use `checkrun`, format and lint locally with `checkrun format`
  and `checkrun lint`, matching the commit hook.
- Before proposing changes, read and understand the existing code, ownership,
  and conventions, and match the file's patterns. Ask when unresolved
  ambiguity about which architectural layer owns a responsibility would
  materially change behavior, interfaces, or architecture.
- When asked to scrub for updates, search code, docs, tests, config, CI, hooks,
  and generated-facing references, not just source files.
- Don't over-engineer. Solve what's asked, nothing more.
- On entering a directory or repo by any means, read its `AGENTS.md` if present.
