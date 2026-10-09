# Shell and Commands

<!-- agent-rule-id: global-shell-command-style -->

- Default to `rg` over `grep` and `fd` over `find` for search.
- Always follow symlinks when searching (`-L` for `rg`/`fd`, or the equivalent
  flag on other search tools): rule and config trees contain symlinked files
  that default search silently skips. If a rules/playbook content search
  returns empty, list the directories directly instead of trusting it.
- Don't chain separately-permitted commands with `&&`; use individual Bash
  calls to avoid permission prompts, e.g. `git -C <path>` rather than
  `cd <path> && git`.
- When piping, grouping, or sequencing verification commands, preserve and
  inspect the status of every required command, not just the final one.
- Inspect tmux sessions with non-attached commands (`capture-pane`,
  `list-panes`, `list-windows`). Attach only if truly necessary: a small client
  shrinks the user's pane size.
