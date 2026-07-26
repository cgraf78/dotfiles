# Core Test Modules

This directory contains the focused modules sourced by `../core-test`.
`core-test` owns fixture setup, shard selection, and shared assertions; these
files own topic-specific coverage.

## Modules

- `commands.sh` covers command dispatch behavior.
- `cron.sh` covers cron merge and filter behavior.
- `doctor.sh` covers `dot doctor` helpers and section output.
- `launchers.sh` covers PATH-visible launchers such as `dot`, `git`, `nvim`,
  and `sley`.
- `main.sh` covers core command and bootstrap-adjacent behavior.
- `merges.sh` covers config merge hooks and generated output.
- `overlays.sh` covers overlay discovery, syncing, linking, and cleanup.
- `runner.sh` covers the `dot-test` runner itself.
- `static.sh` covers static checks.

## Shards

Wrapper scripts one level up set `DOT_CORE_SHARD=<name>` and exec
`core-test`. Add coverage to the focused module first, then add or adjust a
wrapper only when a new shard needs to run independently for parallelism.

`DOT_CORE_SHARD=all ./core-test` remains the audit path for the old monolithic
coverage shape. Keep it working when adding modules or shard gates.

## Style

Prefer explicit test functions named `dot_core_test_<area>`. Keep fixtures under
the test home created by `core-test`; do not read or mutate the real `$HOME`
unless a test is intentionally checking installed dotfiles behavior.
