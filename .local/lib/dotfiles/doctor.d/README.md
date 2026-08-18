# Dotfiles Doctor Extensions

Standalone `dot doctor` runs these client health checks after its core checks.
Each numbered `*.sh` entry defines `doctor()` with no arguments and loads any
private support through `dot_doctor_source doctor.d/lib/...`.

Extensions execute in fresh Bash workers under the same ownership, mode,
symlink-authority, temporary-directory, and isolation rules as merge hooks.
They report only through the versioned public doctor API. A failing extension
does not suppress later checks, but it contributes to the aggregate doctor
failure.

The modules under `lib/` intentionally retain private `_dr_*` implementation
names behind `lib/compat.sh`; those names are client-internal and are not part
of the standalone API.
