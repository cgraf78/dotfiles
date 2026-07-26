# Commit Style

<!-- agent-rule-id: git-commit-message-format -->

- Title: imperative sentence, backtick code names (e.g., "Fix `ds -l` showing
  empty window count")
- Body has `Summary` and `Testing` sections (plain text headers, no `##` prefix)
- (git repos only) Body is hard-wrapped at ~72 columns with 2-space
  continuation indent
- Summary section: first paragraph describes high-level intent & the why,
  following paragraphs provide details; prefer bulleted lists for details,
  lowercase start
- Testing section: bulleted list describing what was verified
- Blank line between title, Summary, and Testing sections
- When commit messages contain backticks or other shell-sensitive characters, do
  not pass them via shell-quoted `git commit -m ...`; write the message to a
  temporary file using the runtime-approved file-writing mechanism and commit
  with `git commit -F`.
