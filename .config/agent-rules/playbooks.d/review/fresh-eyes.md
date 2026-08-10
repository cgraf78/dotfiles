# Adversarial Review

<!-- agent-rule-id: review-adversarial-fresh-eyes -->
<!-- agent-rule-trigger: Completing non-trivial work -->

For any non-trivial work, use at least one fresh-eyes review pass before
calling the task complete. Prefer a mix of adversarial expert subagent
reviewers when the runtime and workflow can safely support them. Give those
reviewers complementary domain expertise and distinct axes instead of asking
several generalists the same broad question.

- Use this for implementation, refactoring, debugging, design changes,
  configuration changes, and durable documentation/rule updates.
- Scale the review to risk: one reviewer or a named self-review is enough for
  a small local change; use multiple parallel reviewers for broad,
  security-sensitive, cross-repo, workflow, data-migration, or
  high-blast-radius changes.
- Assign concrete axes such as correctness, edge cases, concurrency,
  security/privacy, maintainability, tests/CI, developer experience,
  compatibility, and adherence to these agent rules.
- Ask reviewers to look for reasons the work is wrong, incomplete,
  over-scoped, brittle, under-tested, or inconsistent with existing design
  principles. Do not ask for praise or generic approval.
- Treat reviewer output as evidence to triage, not as truth. Validate material
  findings against the code and discard low-confidence or change-for-change's
  sake suggestions.
- Do not delegate when the user explicitly asks for no extra review, the work
  is an urgent operational command, the reviewer would need unavailable tools
  or private context, or the workflow must run in the main session. In those
  cases, do a named self-review pass over the relevant axes and state that
  limitation in the completion summary.
