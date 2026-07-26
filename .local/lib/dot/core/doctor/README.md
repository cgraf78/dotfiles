# Dot Doctor Modules

`dot doctor` is loaded through `../doctor.sh`. That file is the only public
source point: it lazily loads these modules, owns section order, and exposes
the `_dot_doctor` command entry point used by `~/.local/bin/dot`.

## Module API

Section modules report through the private result API in `runtime.sh`:

- `_dr_section <title>`
- `_dr_ok <label> [detail]`
- `_dr_warn <label> [detail]`
- `_dr_fail <label> [detail]`
- `_dr_skip <label> [detail]`

Shared path helpers live in `paths.sh`. Section modules may call those helpers,
but should not mutate `_DR_*` counters directly. This keeps result accounting in
one place while leaving each health-check area small and focused.

Tests that need private `_dr_*` helpers should call `_dot_doctor_load` first.
Other dot commands should not source these section modules during startup.

## Sections

- `shell.sh` checks shell loader and environment assumptions.
- `repos.sh` checks the base dotfiles checkout.
- `overlays.sh` checks configured overlays and overlay link state.
- `tools.sh` checks required tools and shdeps-managed dependency links. Command
  link vocabulary comes from `shdeps dep-links`; dot only owns severity and
  live-environment validation.
- `integrations.sh` checks shell integrations and Git hook wiring.
- `agent-hooks.sh` smoke-tests installed agent hooks.
- `merges.sh` checks generated merge output health.
- `cron.sh` checks tracked cron installation.
- `nvim.sh` checks Neovim startup, LSP policy drift, and health output.
