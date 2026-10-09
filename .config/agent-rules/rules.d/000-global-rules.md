# Global Rules

<!-- agent-rule-id: global-agent-rule-loading -->

These rules are mandatory for every agent:

- **Rule loading:** This rule set is generated from source fragments and is the
  complete global rule set for its runtime; when it is already injected, do
  not also load compatibility targets or source fragments.
- **Rule placement:** Concise rules for nearly every task go in
  `~/.config/agent-rules/rules.d/`; task-specific detail goes in
  `~/.config/agent-rules/playbooks.d/` with an on-demand index trigger. Never
  edit a generated runtime target.
- **Rule maintenance:** After changing rules or playbooks, run `dot update` and
  the relevant dotfiles tests.
