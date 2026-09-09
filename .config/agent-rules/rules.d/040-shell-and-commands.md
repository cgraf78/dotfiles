# Shell and Commands

<!-- agent-rule-id: global-shell-command-style -->

- Prefer `rg` over `grep` and `fd` over `find` as the default search tools.
- Always follow symlinks when searching: rule and config trees contain
  symlinked files that default search skips silently. Enable the
  symlink-following option on whichever search you use (`-L` for `rg`/`fd`,
  the equivalent flag on structured search tools); if a rules/playbook
  content search returns empty, list the directories directly instead of
  trusting the empty result.
- Don't chain separately-permitted commands with `&&`; use individual Bash
  calls to avoid permission prompts. In particular use `git -C <path>` rather
  than `cd <path> && git`.
- When piping, grouping, or sequencing verification commands, preserve and
  inspect the status of every required command. Do not infer success solely
  from the final pipeline or command status.
- When inspecting tmux sessions, prefer non-attached commands like
  `capture-pane`, `list-panes`, `list-windows`. Attaching a small client
  shrinks the user's pane size; only attach if truly necessary.
