# shellcheck shell=bash
# Health checks for the dotfiles installation. Entry point: `_dot_doctor`.
#
# This file owns doctor module loading and top-level ordering. Section modules
# live under `doctor/` and report through the private `_dr_*` result API from
# `doctor/runtime.sh`.

_DOT_CORE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_DOT_DOCTOR_LIB_DIR="$_DOT_CORE_LIB_DIR/doctor"
_DOT_DOCTOR_LOADED=0

# Resolve sibling libraries from the sourced runtime, not from $HOME. Bootstrap
# and tests often source the real checkout while HOME points at a fresh target,
# and helper dependencies must follow the code currently being executed.
# shellcheck source=ui.sh
# shellcheck disable=SC1091 # sibling module resolved from this file's dir.
. "$_DOT_CORE_LIB_DIR/ui.sh"

_dot_doctor_load() {
  if [[ "$_DOT_DOCTOR_LOADED" -eq 1 ]]; then
    return 0
  fi

  # Doctor modules are intentionally lazy: every dot command sources this file
  # through init.sh, but only `dot doctor` needs the section implementations.
  # shellcheck source=doctor/runtime.sh
  . "$_DOT_DOCTOR_LIB_DIR/runtime.sh"
  # shellcheck source=doctor/paths.sh
  . "$_DOT_DOCTOR_LIB_DIR/paths.sh"
  # shellcheck source=doctor/shell.sh
  . "$_DOT_DOCTOR_LIB_DIR/shell.sh"
  # shellcheck source=doctor/repos.sh
  . "$_DOT_DOCTOR_LIB_DIR/repos.sh"
  # shellcheck source=doctor/overlays.sh
  . "$_DOT_DOCTOR_LIB_DIR/overlays.sh"
  # shellcheck source=doctor/tools.sh
  . "$_DOT_DOCTOR_LIB_DIR/tools.sh"
  # shellcheck source=doctor/integrations.sh
  . "$_DOT_DOCTOR_LIB_DIR/integrations.sh"
  # shellcheck source=doctor/agent-hooks.sh
  . "$_DOT_DOCTOR_LIB_DIR/agent-hooks.sh"
  # shellcheck source=doctor/merges.sh
  . "$_DOT_DOCTOR_LIB_DIR/merges.sh"
  # shellcheck source=doctor/cron.sh
  . "$_DOT_DOCTOR_LIB_DIR/cron.sh"
  # shellcheck source=doctor/nvim.sh
  . "$_DOT_DOCTOR_LIB_DIR/nvim.sh"

  _DOT_DOCTOR_LOADED=1
}

_dot_doctor() {
  _dot_doctor_load

  _dot_ui_title 'dot doctor'

  _dr_check_shell
  _dr_check_base_repo
  _dr_check_overlays
  _dr_check_tools
  _dr_check_shell_integrations
  _dr_check_git_hooks
  _dr_check_agent_hooks
  _dr_check_hive_memory
  _dr_check_merges
  _dr_check_cron
  _dr_check_nvim

  # Summary: coloured by worst status. Use gum for the box so the summary
  # reads as the conclusion rather than just another line.
  local summary_line summary_color
  summary_line=$(printf '%d passed · %d warnings · %d failed' \
    "$_DR_PASS_COUNT" "$_DR_WARN_COUNT" "$_DR_FAIL_COUNT")
  if [[ "$_DR_FAIL_COUNT" -gt 0 ]]; then
    summary_color=red
  elif [[ "$_DR_WARN_COUNT" -gt 0 ]]; then
    summary_color=yellow
  else
    summary_color=green
  fi
  echo
  _dot_ui_summary_box "$summary_color" "$summary_line"

  [[ "$_DR_FAIL_COUNT" -eq 0 ]]
}
