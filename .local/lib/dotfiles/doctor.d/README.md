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
deadline (a coreutils timeout(1) or gtimeout where installed, a builtin
watchdog otherwise, including for BusyBox) and returns 124 when it passes;
checks that start user programs use it so one hang cannot hold the whole
run. The watchdog also kills whatever the command leaves in its process
group once it exits, so nothing it starts outlives the call, and returns
125 without running the command when the deadline is malformed or its
private directory and FIFO cannot be created.
`_dr_list_row LEVEL MESSAGE HINT [ITEM...]` files one row (`ok`, `warn`,
`fail`, `skip`, or `info`) whose evidence is a list: on a Dot whose doctor
API has `dot_doctor_item` and `dot_doctor_hint`, each item is an indented
line under the row and a non-empty `HINT` is a next-step line; on an older
Dot the first three items, `and N more`, and the hint are joined into the
row's detail. It is newer than `lib/compat.sh` itself, so an overlay probes
it with `declare -F _dr_list_row` before calling it.
`_dr_hint_row LEVEL MESSAGE DETAIL HINT` files one row whose evidence is
`DETAIL` (may be empty) and whose next step is `HINT`: a separate next-step
line on a Dot whose doctor API has `dot_doctor_hint`, otherwise appended to
the detail after `; `. Every warn and fail row carries a next step, through
it or through `_dr_list_row`'s `HINT`.
It is newer than `_dr_list_row`, so an overlay probes it with
`declare -F _dr_hint_row` and falls back to the same rule itself.
`_DR_TMPDIR_HINT` is the shared next step for a probe that could not create
its temporary directory.
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
  reports every installed package's links (plus deferred, recovery,
  transition, and install-root state) from that single stat-only pass,
  listing each problem with shdeps' own fix, failures first. The call is
  then a silent no-op that emits nothing, so overlays keep passing their
  dependency list without duplicating rows or knowing which mode is
  active. Severities then follow shdeps: a missing or dangling link warns,
  because the next update repairs it, whatever level the caller passed. Each worker probes
  `shdeps health` at most once.
- With an older shdeps that lacks `shdeps health`, the base Tools section
  only warns that health is unchecked, and this call still checks the
  caller's group.
- An overlay that also carries its own fallback copy for older bases must
  define it only when `dot_doctor_source doctor.d/lib/shdeps-links.sh`
  fails; a same-named definition after a successful load replaces the
  health-aware version and brings the duplicate rows back.
- The module loads `lib/compat.sh` itself and returns nonzero from
  `dot_doctor_source` only when that fails.

`lib/config-temporaries.sh` provides the leftover-temporary check:

```bash
if dot_doctor_source doctor.d/lib/config-temporaries.sh; then
  _dr_check_config_temporaries DIR...
fi
```

- Each `DIR` is a directory the caller's merge hooks write config files
  into, absolute or relative to `$HOME` (`.claude` means `~/.claude`). Only
  its direct children are checked.
- A regular file there counts when it is named `*.tmp`, `*.tmp.*`, or
  `.*.realize.*` (hidden or not for the first two; hidden only directly in
  `$HOME`) and is more than ten minutes old: what an update killed
  mid-write leaves behind. The call files
  one warning in the caller's current section listing every such file, or
  nothing when there is none. Nothing is deleted.
- Base checks the destinations of its own merge hooks in Managed
  configuration: `$HOME`, `~/.ssh`, `/etc/ssh`, `~/.config/karabiner`,
  `~/.codex`, and the folder of every agent-rules target in the last
  update's manifest. Those, and repeats, are dropped from an overlay's list, so an
  overlay passes every folder its hooks write without knowing base's list,
  and a folder two layers write is reported once.
- An overlay registers its folders by calling the function from its own
  `doctor()`; there is no registry file. Against an older base without the
  module, `dot_doctor_source` fails and the `if` above skips the check.
  Doctor workers run under `set -e`, so `dot_doctor_source … || return`
  would instead end the overlay's `doctor()` with a failure.
- The module loads `lib/compat.sh` itself and returns nonzero from
  `dot_doctor_source` only when that fails.

The remaining modules under `lib/` and their `_dr_*` implementation names are
private to base checks and may change at any time.
