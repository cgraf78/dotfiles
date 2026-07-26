# Global Rules

<!-- agent-rule-id: global-agent-rule-loading -->

These rules are mandatory for every agent:

- **Rule loading:** This rule set is generated from source fragments. The
  generated runtime target is the complete global rule set for that runtime; do
  not load generated compatibility targets or source fragments a second time
  when this aggregate has already been injected.
- **Rule placement:** Put concise rules that apply to nearly every task in
  `~/.config/dot/merge-hooks.d/agent-rules/rules.d/`. Put task-specific detail
  in `~/.config/dot/agent-playbooks.d/` and add a trigger to the
  on-demand playbook index. Never edit a generated runtime target.
- **Rule maintenance:** After changing rules or playbooks, run `dot update` and
  the relevant dotfiles tests.
