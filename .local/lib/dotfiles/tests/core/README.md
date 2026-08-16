# Core Test Modules

This directory contains the focused modules sourced by `../core-test`.
`core-test` owns fixture setup, shard selection, and shared assertions; these
files own topic-specific coverage.

## Modules

- `cron.sh` covers cron merge and filter behavior.
- `doctor.sh` covers dotfiles-owned doctor helpers through the public extension
  API and one actual standalone coordinator run.
- `launchers.sh` covers client PATH-visible launchers such as `git`, `nvim`,
  and `hm`.
- `merges.sh` covers config merge hooks and generated output, including
  activation of Sley's provider-owned Sapling gate at its stable Shdeps path.
- `runner.sh` covers the `dot-test` runner itself.
- `static.sh` covers static checks.

## Shards

Wrapper scripts one level up set `DOT_CORE_SHARD=<name>` and exec
`core-test`. Add coverage to the focused module first, then add or adjust a
wrapper only when a new shard needs to run independently for parallelism.

`DOT_CORE_SHARD=all ./core-test` runs every retained dotfiles-owned module.
Generic repository, overlay, resource, and CLI coverage belongs to standalone
dot and must not be copied back here.

## Style

Prefer explicit test functions named `dot_core_test_<area>`. Keep fixtures under
the test home created by `core-test`; do not read or mutate the real `$HOME`
unless a test is intentionally checking installed dotfiles behavior.
