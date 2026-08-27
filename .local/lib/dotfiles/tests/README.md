# Top-Level Dot Test Suites

The standalone Dot provider discovers executable `*-test` scripts from this
directory. The literal CI inventory in `.github/dot-test-suites.txt` lists
every executable suite owned by the top-level repository.

This repository tests the always-active base substrate and the profile control
plane: shell startup, Git bootstrap routing, tmux, terminal integration,
agent-rule aggregation, profile selection, ownership, composition, migration,
and footprint measurement. `dotfiles-nvim` and `dotfiles-dev` run their focused
tests and doctor checks in their own CI; top-level CI validates their immutable
inventories but does not execute them again.

Run the CI-owned set through the pinned D1 runtime:

```text
.local/lib/dotfiles/tests/stack-dot-runtime control-plane-run-ci -- \
  .local/lib/dotfiles/tests/run-ci
.local/lib/dotfiles/tests/stack-dot-runtime profile-fixture-update -- \
  .local/lib/dotfiles/tests/profile-fixture-integration update
.local/lib/dotfiles/tests/stack-dot-runtime profile-doctor -- \
  .local/lib/dotfiles/tests/profile-fixture-integration doctor
.local/lib/dotfiles/tests/stack-dot-runtime installed-profile-dot-test -- \
  .local/lib/dotfiles/tests/profile-fixture-integration test
```

Shared CI first checks out the immutable pull-request head, then uses
`run-ci-candidate-home` to clone that commit into Dot's normal separate-Git
layout and create a separate clean source worktree before invoking these
commands. The helper also installs the exact D1 runtime and the immutable
Shdeps test release through the pinned installer recorded in
`.github/overlay-profile-stack.lock`. It also installs the exact base-owned
`agent-rules-sync` provider and retains the frozen source commit needed by
ownership checks; test fixtures therefore do not depend on a runner's
pre-existing dotfiles setup.

The D5 installed-profile gate runs real unfiltered `dot test --list` discovery
and then executes `dot test` in isolated base, editor, and dev homes. The
update fixture also exercises a dev-to-editor-to-base downgrade, including a
later retry of an initially unavailable optional overlay, managed-link cleanup,
shadow restoration, and preservation of cached checkouts and package state.

Individual suites may still be selected with `dot test <name>` during local
development. Tests must use the fixture home supplied by the harness and must
not modify the caller's live home, state, cache, or credentials.
