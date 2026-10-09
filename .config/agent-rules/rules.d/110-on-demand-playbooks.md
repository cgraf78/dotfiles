# On-Demand Playbooks

<!-- agent-rule-id: global-on-demand-playbooks -->

Detailed guidance lives in agent-agnostic playbooks; the paths below resolve
under `~/.config/agent-rules/playbooks.d/`. Before the first affected action,
read each playbook whose trigger matches the task. Do not load unrelated
playbooks. More specific repository-local instructions take precedence.

<!-- agent-rules-sync-playbook-index -->

If a playbook is missing or unreadable, say so and continue with the core rules
and repository guidance unless the user says to stop.
