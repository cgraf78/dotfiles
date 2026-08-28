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
.local/lib/dotfiles/tests/stack-dot-runtime legacy-profile-cutover -- \
  .local/lib/dotfiles/tests/legacy-profile-cutover
.local/lib/dotfiles/tests/stack-dot-runtime profile-doctor -- \
  .local/lib/dotfiles/tests/profile-fixture-integration doctor
.local/lib/dotfiles/tests/stack-dot-runtime installed-profile-dot-test -- \
  .local/lib/dotfiles/tests/profile-fixture-integration test
.local/lib/dotfiles/tests/stack-dot-runtime profile-footprint-fixtures -- \
  .local/lib/dotfiles/tests/profile-fixture-integration footprint
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

`legacy-profile-cutover` and the `pre_profile_dot`/D4 base lock fields are
transition-only fleet safeguards. Retire them in a follow-up PR after every
managed machine has successfully crossed the profile boundary. That cleanup
deletes the fixture, its workflow invocation, the three historical lock
fields, D4 pull-request-base validation, and their dedicated stack-test cases.
The exact candidate checkout, isolated candidate HOME, profile selection, and
ordinary upgrade/downgrade suites remain permanent coverage.
The legacy cutover fixture starts from the exact pre-profile root and Dot
revisions and proves direct, staged, and interrupted `dot update -f` handoffs
to the final `dev` composition.

The footprint fixture reports exact checkout, configuration, and control-plane
payloads for clean post-cutover homes and compares them with the exact locked
D4 monolith. It enforces the 500 MiB base and editor-repository budgets. The
installed editor graph remains measured by `dotfiles-nvim` owner CI. The dev
2.5--4.5 GiB figure is reported as install context rather than a fresh-install
measurement: optional private overlays, host package stores, language/package
caches, and project build outputs stay separate from that estimate.

Individual suites may still be selected with `dot test <name>` during local
development. Tests must use the fixture home supplied by the harness and must
not modify the caller's live home, state, cache, or credentials.
