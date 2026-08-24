# Agent Rule Maintenance

<!-- agent-rule-id: agent-rules-maintenance -->
<!-- agent-rule-trigger: Adding, moving, auditing, or changing agent rules or playbooks -->

Treat rule sources as a routed policy system. Preserve one canonical owner,
keep always-loaded context small, and verify the installed aggregate rather
than editing generated outputs.

## Find the owner

- Resolve the canonical source before editing. Generated runtime targets,
  manifest outputs, and overlay links are consumers, not edit locations.
- Put broadly reusable and publicly safe guidance in the base dotfiles
  repository. Put private non-work context in the personal overlay and
  employer-specific context in the work overlay.
- Search existing rule IDs, triggers, and prose before adding a new rule.
  Extend the existing owner when the subject already has one.

## Choose the loading boundary

- Keep only concise requirements that affect nearly every task in `rules.d/`.
  Put procedures, command recipes, platform details, and domain-specific
  failure handling in a playbook.
- Give each playbook one precise action-oriented trigger and a globally unique
  stable rule ID. Avoid broad triggers that load unrelated guidance.
- When adding always-loaded prose, review the aggregate context cost and look
  for equal or larger task-specific detail that can move behind a trigger.
- Keep compatibility and provider mechanics in their owning documentation;
  rules should state the behavioral contract an agent must follow.

## Change and verify

- For cross-repository changes, separate provider and consumer pull requests,
  state their dependency, and land them in the safe order.
- Run the focused agent-rule validation from the source checkout, then the full
  dotfiles test suite required by repository policy.
- Run `dot update` after source changes land. Verify the generated playbook
  index, runtime targets, overlay links, and provider validation from installed
  state.
- Review the final aggregate for duplicated instructions, broken paths,
  accidental private content, and unnecessary always-loaded growth.
