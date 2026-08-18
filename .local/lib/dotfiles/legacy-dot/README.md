# Dot Runtime Library

`~/.local/lib/dotfiles/legacy-dot` owns the frozen rescue runtime. Reusable tool behavior
lives in shdeps-managed dependency repos; call those public APIs through
`shdeps dep-*` instead of keeping compatibility shims here.

- [`core/`](core/README.md) owns the `dot` command runtime, bootstrap helpers,
  update orchestration, repository discovery, merge orchestration, doctor
  checks, shell loading, and terminal UI helpers. Doctor checks are organized as
  focused section modules under `core/doctor/`.
- [`git-hooks/`](git-hooks/README.md) owns the executable Git activation and
  dotfiles-specific policy adapters that Git invokes directly. It is
  deliberately outside `core/`: these hooks are part of the dotfiles runtime,
  but not part of the `dot` command runtime.
- [`sley-hooks/`](sley-hooks/README.md) owns advanced dotfiles policy providers
  reached through Sley's generic SCM hook APIs. The providers are internal
  implementation, not PATH-visible commands.
- [`tests/`](tests/README.md) owns dotfiles test suites and their shared
  harness.

Shell and directly executed helper scripts use dash-separated filenames.
Importable Python modules use Python's normal underscore style; Python helpers
that are executed by path can keep dash-separated names when that reads like a
command.
