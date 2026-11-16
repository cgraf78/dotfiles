# Shell and Commands

<!-- agent-rule-id: global-shell-command-style -->

- Default to `rg` over `grep` and `fd` over `find` for search.
- Always follow symlinks when searching (`-L` for `rg`/`fd`, or the equivalent
  flag on other search tools): rule and config trees contain symlinked files
  that default search silently skips. If a rules search returns empty, list
  the directories.
- Don't chain separately-permitted commands with `&&`; use individual Bash
  calls to avoid permission prompts, e.g. `git -C <path>` rather than
  `cd <path> && git`.
- When piping, grouping, or sequencing verification commands, preserve and
  inspect the status of every required command, not just the final one.
- Inspect tmux sessions with non-attached commands (`capture-pane`,
  `list-panes`, `list-windows`). Attach only if truly necessary: a small client
  shrinks the user's pane size.
- Type into, read, or wait on another tmux pane with
  `tmux-pane send|read|wait -t %N`, using an exact pane id from
  `tmux list-panes -a`, never an empty or implicit target.
  `tmux-pane send -t %N 'TEXT' --enter --wait agent|prompt` prints the reply;
  `status=N` on stderr means the exit code is the command's. After 124, or
  after 68 once the prompt is answered, resume with
  `tmux-pane wait -t %N --agent|--prompt --since "$M" --capture`, using the
  printed `marker=`. Put `--` before text that starts with `-`. Keep
  `--timeout` below your tool-call limit.
