# Dotfiles Testing

<!-- agent-rule-id: dotfiles-testing-worktree-dot-test -->
<!-- agent-rule-trigger: Changing or testing dotfiles -->

For dotfiles test work, run `dot-test` from the checkout under test and let the
runner auto-detect the source tree, whether that checkout is the live `$HOME` or
a linked git worktree.

- Do not require callers to set `HOME` to the worktree for ordinary test runs.
- Do not add suite-specific schemes for source-home discovery; use the
  `DOT_TEST_SOURCE_HOME` and `DOT_TEST_HOST_HOME` contract already owned by
  `.local/bin/dot-test`.
- Ordinary suites should not care whether they are running from the live home or
  a linked worktree. If a suite needs host-installed tools, use the existing
  helpers in `.local/lib/dotfiles/tests/helpers.sh` instead of hard-coding host paths.
- When comparing paths on macOS, canonicalize only assertions that care about
  filesystem identity rather than visible spelling, because `/var` and
  `/private/var` may both appear in the same test run.
