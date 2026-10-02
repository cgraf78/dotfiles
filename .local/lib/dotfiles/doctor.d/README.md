# Dotfiles Doctor Extensions

Standalone `dot doctor` runs these client health checks after its core checks.
Each numbered `*.sh` entry defines `doctor()` with no arguments and loads any
private support through `dot_doctor_source doctor.d/lib/...`.

Extensions execute in fresh Bash workers under the same ownership, mode,
symlink-authority, temporary-directory, and isolation rules as merge hooks.
They report only through the versioned public doctor API. A failing extension
does not suppress later checks, but it contributes to the aggregate doctor
failure. Checks stay diagnostics-only and cheap: stat-level reads or a
handful of processes, no network, and no writes to tracked files.

## Overlay-facing helpers

Overlay extensions (`dotfiles-dev`, `dotfiles-nvim`) load base support from
here, so these names are a stable contract between independently updated
repositories. Each overlay must keep working against an older base that
lacks a newer helper: probe with `dot_doctor_source` and fall back.

`lib/compat.sh` provides the `_dr_*` row and path helpers that every module
uses: `_dr_section`, `_dr_ok`, `_dr_warn`, `_dr_fail`, `_dr_skip`, `_dr_info`,
`_dr_tilde`, `_dr_symlink_points_to`, `_dr_symlink_target_path`,
`_dr_account_home`, `_dr_account_scoped_command`, and
`_dr_is_dotfiles_checkout`, plus `_dot_shdeps_conf_dir` (sets `REPLY`) from
the shdeps asset adapter it loads. `_dr_info` uses the doctor API's `info`
kind when the running Dot provides one and renders as an ok row otherwise.
`_dr_run_bounded SECONDS COMMAND...` runs an external command under a
deadline (timeout(1) or gtimeout where installed, a builtin watchdog
otherwise) and returns 124 when it passes; checks that start user programs
use it so one hang cannot hold the whole run.
`_dr_hook_runtime_source` loads Dot's public hook runtime so a check can ask
a merge hook what it would render; it depends on the worker's
`DOT_SOURCE_ROOT`, and callers report a skip when it fails.

`lib/shdeps-links.sh` provides the shdeps-backed command-link check:

```bash
dot_doctor_source doctor.d/lib/shdeps-links.sh || return
_dr_check_shdeps_bin_group <fail|warn> <dependency>
```

- `<dependency>` is the repository name under `cgraf78` (for example
  `agentguard`). The check verifies the public command links that
  `shdeps dep-links cgraf78/<dependency>` reports: each one exists, points at
  its expected target, and is executable. It emits one ok row for a healthy
  group, otherwise one row per problem at the given severity.
- When the installed shdeps provides `shdeps health`, the base Tools section
  reports every installed package's links (plus deferred, recovery, and
  install-root state) from that single stat-only pass. The call is then a
  silent no-op that emits nothing, so overlays keep passing their dependency
  list without duplicating rows or knowing which mode is active. Severities
  then follow shdeps: a missing or dangling link warns, because the next
  update repairs it, whatever level the caller passed. Each worker probes
  `shdeps health` at most once.
- An overlay that also carries its own fallback copy for older bases must
  define it only when `dot_doctor_source doctor.d/lib/shdeps-links.sh`
  fails; a same-named definition after a successful load replaces the
  health-aware version and brings the duplicate rows back.
- The module loads `lib/compat.sh` itself and returns nonzero from
  `dot_doctor_source` only when that fails.

The remaining modules under `lib/` and their `_dr_*` implementation names are
private to base checks and may change at any time.
