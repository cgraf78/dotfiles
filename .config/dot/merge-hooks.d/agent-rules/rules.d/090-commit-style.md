# Commit Style

<!-- agent-rule-id: git-commit-message-format -->

- Title: imperative sentence, backtick code names (e.g., "Fix `ds -l` showing
  empty window count")
- Body has `Summary` and `Testing` sections (plain text headers, no `##` prefix)
- (git repos only) Body is hard-wrapped at ~72 columns with 2-space
  continuation indent
- Summary: first paragraph gives high-level intent & the why, later paragraphs
  give details; prefer bulleted lists, lowercase start
- Testing: bulleted list of what was verified
- Blank line between title, Summary, and Testing sections
- For messages with backticks or other shell-sensitive characters, don't use
  shell-quoted `git commit -m ...`; write the message to a temp file with the
  runtime-approved file-writing mechanism and commit with `git commit -F`.
