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
```

Individual suites may still be selected with `dot test <name>` during local
development. Tests must use the fixture home supplied by the harness and must
not modify the caller's live home, state, cache, or credentials.
