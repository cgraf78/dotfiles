# On-Demand Playbooks

<!-- agent-rule-id: global-on-demand-playbooks -->

Detailed guidance lives in agent-agnostic Markdown playbooks under
`~/.config/dot/agent-playbooks.d/`. Before the first affected action,
read each playbook whose trigger matches the task. Do not load unrelated
playbooks. Repository-local instructions take precedence when they are more
specific.

<!-- dot-playbook-index -->

Resolve relative paths against `~/.config/dot/agent-playbooks.d/`. If a
matching playbook is missing or unreadable, say so and continue using the core
rules and repository guidance unless the user asks you to stop.
