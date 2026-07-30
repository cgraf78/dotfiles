# Global Rules

<!-- agent-rule-id: global-agent-rule-loading -->

These rules are mandatory for every agent:

- **Rule loading:** This rule set is generated from source fragments. The
  generated runtime target is the complete global rule set for that runtime;
  when this aggregate is already injected, do not load compatibility targets or
  source fragments again.
- **Rule placement:** Concise rules that apply to nearly every task go in
  `~/.config/dot/merge-hooks.d/agent-rules/rules.d/`; task-specific detail goes
  in `~/.config/dot/agent-playbooks.d/` with a trigger in the on-demand
  playbook index. Never edit a generated runtime target.
- **Rule maintenance:** After changing rules or playbooks, run `dot update` and
  the relevant dotfiles tests.
