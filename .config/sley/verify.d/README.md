# Sley Verification Policy

This directory contains local Sley verify policy. These files describe
repository-specific verification commands, not Sley's generic behavior.

`dotfiles.json` matches the base dotfiles remote and defines the `dot-test`
verification command. The rule is currently disabled because normal local and
CI workflows already run `dot-test` directly; keeping the policy here preserves
the intended command shape for agents or future Sley-driven verification.

When enabling or adding rules, keep commands repo-scoped and avoid relying on
the bare dotfiles Git environment leaking in. The existing command explicitly
unsets `GIT_DIR`, `GIT_WORK_TREE`, and `SLEY_SKIP_UNTRACKED` before running
`dot-test` so verification exercises the public command path.
