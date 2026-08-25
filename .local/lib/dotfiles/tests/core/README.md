# Core Test Modules

This directory contains the focused modules sourced by `../core-test`.
`core-test` owns fixture setup, shard selection, and shared assertions; these
files own topic-specific coverage.

## Modules

- `cron.sh` covers cron merge and filter behavior.
- `doctor.sh` covers `dot doctor` helpers and section output.
- `launchers.sh` covers PATH-visible launchers such as `dot`, `git`, `nvim`,
  and `sley`.
- `merges.sh` covers config merge hooks and generated output, including
  activation of Sley's provider-owned Sapling gate at its stable Shdeps path.
- standalone Dot owns the `dot test` runner and its lifecycle coverage.
- `static.sh` covers repository-wide client policy and portability checks.

Standalone command, repository, lock, resource, and overlay behavior belongs
to the Dot repository's own test suite rather than this client inventory.

## Shards

Wrapper scripts one level up set `DOT_CORE_SHARD=<name>` and exec
`core-test`. Add coverage to the focused module first, then add or adjust a
wrapper only when a new shard needs to run independently for parallelism.

`DOT_CORE_SHARD=all ./core-test` runs every retained client module in one
process. Keep it working when adding modules or shard gates.

## Style

Prefer explicit test functions named `dot_core_test_<area>`. Keep fixtures under
the test home created by `core-test`; do not read or mutate the real `$HOME`
unless a test is intentionally checking installed dotfiles behavior.
