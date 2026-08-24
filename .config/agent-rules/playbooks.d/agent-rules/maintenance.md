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

## Decide what deserves a playbook

- Promote guidance when it recurs across materially different tasks, encodes a
  hard safety or authorization boundary, captures a non-obvious decision
  procedure, or identifies an authoritative owner or verification path that
  agents would otherwise repeatedly rediscover.
- Express a candidate as `trigger -> decision or procedure -> failure prevented
  -> verification`. If one of those parts is missing, retain the observation in
  documentation or durable memory until the workflow is clear.
- Do not promote guidance merely because an incident was difficult, a command
  was useful once, or current host, version, path, identifier, address, and
  workaround details are worth remembering.
- Keep repository and service facts in their authoritative documentation. Keep
  point-in-time evidence and uncertain observations in durable memory rather
  than turning them into behavioral policy.
- One demonstrated hard safety boundary can justify promotion. Otherwise prefer
  evidence from multiple independent tasks before generalizing.

## Curate the playbook set

- Review recent user corrections, rollbacks, repeated investigations, durable
  memory, and session summaries by reusable workflow rather than by incident.
- Classify each candidate as already covered, an existing-playbook refinement, a
  new playbook, documentation or memory only, or a one-off to discard.
- Prefer extending the existing topical owner when its trigger already matches.
  Create a new playbook only for a cohesive procedure with a distinct trigger.
- Audit older playbooks for duplication, conflicting instructions, stale facts,
  broad triggers, misplaced private content, and procedures that should move to
  authoritative product or repository documentation.
- Narrow, merge, split, move, or retire playbooks when their loading boundary no
  longer matches actual tasks. Verify that historical motivating tasks would
  load the new route and unrelated tasks would not.
- Lead with durable behavior and decision criteria. Include exact commands only
  when their form is itself stable; avoid turning playbooks into system
  inventories.

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
