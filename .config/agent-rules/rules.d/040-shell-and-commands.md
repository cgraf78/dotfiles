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
- Change files with your file-edit and write tools (e.g. `apply_patch`,
  `replace`, `write_file`), not shell writes (`python3 - <<EOF`, `sed -i`,
  `perl -i`, `tee`, redirection, or copying a temp file over the target), even
  when runtime instructions leave the choice to you: post-edit hooks format,
  lint, and track only tool edits. A repository's own generators and
  formatters, and VCS commands, are not shell writes. Exceptions: temp files,
  remote hosts the tools cannot reach, files the tools cannot handle (binary,
  oversized, or content a hook is known to rewrite), and one substitution
  across too many files to edit one by one; after such a write to a tracked
  file, run its formatter and linter.
- When piping, grouping, or sequencing verification commands, preserve and
  inspect the status of every required command, not just the final one.
- Inspect tmux sessions with non-attached commands (`capture-pane`,
  `list-panes`, `list-windows`). Attach only if truly necessary: a small client
  shrinks the user's pane size.
- Drive another pane with `tmux-pane send|read|wait -t %N`, an exact pane
  id from `tmux list-panes -a`, never empty or implicit.
  `tmux-pane send -t %N 'TEXT' --enter --wait agent|prompt` prints the reply;
  `status=N` on stderr means the command's exit code. Exit 68 is a question or
  permission prompt: leave it to the user unless asked to answer. After exit
  124, or exit 68 once answered, resume with
  `tmux-pane wait -t %N --agent|--prompt --since "$M" --capture` (`M`: the
  printed `marker=`). Put `--` before text starting with `-`; keep `--timeout`
  below your tool-call limit.
