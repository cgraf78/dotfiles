# Shell and Commands

<!-- agent-rule-id: global-shell-command-style -->

- Prefer `rg` over `grep` and `fd` over `find` as the default search tools.
- Don't chain separately-permitted commands with `&&` — use individual Bash calls
  instead, to avoid unnecessary permission prompts.
- Use `git -C <path>` instead of `cd <path> && git` — avoids compound command
  permission checks triggered by `cd` + `git` combinations.
- When inspecting tmux sessions, prefer non-attached tmux commands like
  `capture-pane`, `list-panes`, and `list-windows`. Avoid attaching a small
  client that would shrink the user's pane size; only attach interactively if
  truly necessary.
