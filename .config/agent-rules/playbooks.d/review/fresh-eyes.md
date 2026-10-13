# Adversarial Review

<!-- agent-rule-id: review-adversarial-fresh-eyes -->
<!-- agent-rule-trigger: Completing non-trivial work -->

Before calling work complete, run a mix of adversarial expert subagent
reviewers by default; only a truly small change (below) may instead get a
named self-review. Give those reviewers complementary domain expertise and
distinct axes instead of asking several generalists the same broad question.

- Use this for implementation, refactoring, debugging, design changes,
  configuration changes, and durable documentation/rule updates.
- Scale the review to risk. A truly small change is a typo, comment, or
  formatting fix, or a one-line change whose effect is confined to its stated
  target; rewording a rule or playbook changes agent behavior and is not
  truly small. Add reviewers and axes for broad, security-sensitive,
  cross-repo, workflow, data-migration, or high-blast-radius changes.
- Call a self-review a self-review, not fresh-eyes or independent review. Those
  terms require a reviewer that did not produce the work.
- Assign concrete axes such as correctness, edge cases, concurrency,
  security/privacy, maintainability, tests/CI, developer experience,
  compatibility, and adherence to these agent rules.
- Always cover side effects: give one reviewer, or the self-review, a dedicated
  axis for behavior changes outside the stated scope, such as other hosts or
  platforms, inherited environment, exit codes, performance, and user
  overrides.
- Each reviewer ends with an explicit verdict on its axes.
- Ask reviewers to look for reasons the work is wrong, incomplete,
  over-scoped, brittle, under-tested, or inconsistent with existing design
  principles. Do not ask for praise or generic approval.
- Treat reviewer output as evidence to triage, not as truth. Validate material
  findings against the code and discard low-confidence or change-for-change's
  sake suggestions.
- After actionable fixes, rerun affected checks. For high-risk work or an
  explicitly requested independent-review gate, continue with a new independent
  pass until the current diff receives a clean review.
- Do not delegate when the user explicitly asks for no extra review, the work
  is an urgent operational command, the runtime cannot run subagents, the
  reviewer would need unavailable tools or private context, or the workflow
  must run in the main session. In those cases, do a named self-review pass
  over the relevant axes and state that limitation in the completion summary.
