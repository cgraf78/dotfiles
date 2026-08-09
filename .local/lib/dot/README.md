# Dot Runtime Library

`~/.local/lib/dot` owns dotfiles-specific runtime code. Reusable tool behavior
lives in shdeps-managed dependency repos; call those public APIs through
`shdeps dep-*` instead of keeping compatibility shims here.

- [`core/`](core/README.md) owns the `dot` command runtime, bootstrap helpers,
  update orchestration, repository discovery, merge orchestration, doctor
  checks, shell loading, and terminal UI helpers. Doctor checks are organized as
  focused section modules under `core/doctor/`.
- [`tests/`](tests/README.md) owns dotfiles test suites and their shared
  harness.

Shell and directly executed helper scripts use dash-separated filenames.
Importable Python modules use Python's normal underscore style; Python helpers
that are executed by path can keep dash-separated names when that reads like a
command.
