# Conflict Resolution Safety

<!-- agent-rule-id: git-conflict-resolution-safety -->
<!-- agent-rule-trigger: Resolving a Git or Sapling merge, rebase, restack, or histedit conflict -->

Treat conflict resolution as a content change that requires direct inspection.
Do not mark a path resolved or continue history rewriting merely because an
editing command or script returned.

## Resolve deliberately

- Identify which side owns each behavior and reconstruct the intended combined
  result. Do not mechanically choose one side when both contain relevant work.
- Check every editing command's exit status and inspect the actual working file.
  If a helper script consumes shell paths or revisions, pass them explicitly and
  fail on missing input rather than assuming interpolation occurred.
- Search affected files for remaining conflict markers such as `<<<<<<<`,
  `=======`, and `>>>>>>>` before marking them resolved.
- Check for duplicated declarations, tests, imports, configuration entries, and
  adjacent blocks that can survive a marker-free but incorrect merge.
- Review the full resolved diff, not only the conflict hunks.

## Continue and verify

- Run the narrowest relevant parser, formatter, build, or test before
  `git add`, `sl resolve --mark`, or the equivalent resolution step when the
  workflow permits it.
- After continuing the rebase, restack, or histedit, inspect the resulting graph
  and the rewritten commit's complete diff. Confirm expected files and changes
  are present exactly once.
- Re-run checks invalidated by the rewrite. A previously green result does not
  prove the reconstructed commit is valid.
- If the resolution is uncertain, recover the file from a known clean revision
  and reapply the intended edit instead of layering repairs over ambiguous
  merged content.
