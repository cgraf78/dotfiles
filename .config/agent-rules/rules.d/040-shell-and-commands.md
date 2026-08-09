# Shell and Commands

<!-- agent-rule-id: global-shell-command-style -->

- Prefer `rg` over `grep` and `fd` over `find` as the default search tools.
- Don't chain separately-permitted commands with `&&`; use individual Bash
  calls to avoid permission prompts. In particular use `git -C <path>` rather
  than `cd <path> && git`.
- When inspecting tmux sessions, prefer non-attached commands like
  `capture-pane`, `list-panes`, `list-windows`. Attaching a small client
  shrinks the user's pane size; only attach if truly necessary.
