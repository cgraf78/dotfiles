# On-Demand Playbooks

<!-- agent-rule-id: global-on-demand-playbooks -->

Detailed guidance lives in agent-agnostic Markdown playbooks under
`~/.config/dot/agent-playbooks.d/`, against which the paths below resolve.
Before the first affected action, read each playbook whose trigger matches the
task. Do not load unrelated playbooks. Repository-local instructions take
precedence when they are more specific.

<!-- agent-rules-sync-playbook-index -->

If a playbook is missing or unreadable, say so and continue with the core rules
and repository guidance unless the user says to stop.
