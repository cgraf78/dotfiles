# shellcheck shell=bash
# Shared environment for dot and dotbootstrap.
# Sources all dot modules in dependency order, then bootstraps shdeps.

_dir="${BASH_SOURCE[0]%/*}"
. "$_dir/core.sh"
. "$_dir/repos.sh"
. "$_dir/merges.sh"

# ---------------------------------------------------------------------------
# shdeps bootstrap — find or clone shdeps, configure for dotfiles
# ---------------------------------------------------------------------------

# Bridge shdeps logging to core.sh's versions so all output is consistent.
# Define these before sourcing shdeps.sh — it respects pre-defined functions.
_shdeps_log()        { _log "$@"; }
_shdeps_warn()       { _warn "$@"; }
_shdeps_log_ok()     { _log_ok "$@"; }
_shdeps_log_dim()    { _log_dim "$@"; }
_shdeps_log_header() { _log_header "$@"; }

# Locate install.sh: env override → dev clone → installed clone → curl install.
# Sets REPLY to the path on success, returns 1 if not found.
_find_shdeps_installer() {
  # REAL_HOME is set by test framework when HOME is mocked
  local real_home="${REAL_HOME:-$HOME}"
  local dev_dir="${SHDEPS_GIT_DEV_DIR:-$real_home/git}"

  if [[ -n "${SHDEPS_LIB:-}" && -f "${SHDEPS_LIB%/*}/install.sh" ]]; then
    REPLY="${SHDEPS_LIB%/*}/install.sh"
    return 0
  fi
  if [[ -f "$dev_dir/shdeps/install.sh" ]]; then
    REPLY="$dev_dir/shdeps/install.sh"
    return 0
  fi
  if [[ -f "$HOME/.local/share/shdeps/install.sh" ]]; then
    REPLY="$HOME/.local/share/shdeps/install.sh"
    return 0
  fi

  # Not installed — install first
  _log "  shdeps not found, installing..."
  local _install_url="https://raw.githubusercontent.com/cgraf78/shdeps/main/install.sh"
  if curl -fsSL "$_install_url" | bash &>/dev/null; then
    REPLY="$HOME/.local/share/shdeps/install.sh"
    return 0
  fi

  return 1
}

_bootstrap_shdeps() {
  # Map dotfiles env vars to shdeps config (must be set before --bootstrap
  # sources shdeps.sh, since it reads these at source time)
  export SHDEPS_CONF_DIR="$HOME/.config/shdeps"
  export SHDEPS_HOOKS_DIR="$HOME/.config/shdeps/hooks.d"
  export SHDEPS_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dot/deps"
  [[ "${DOT_FORCE:-0}" -eq 1 ]] && export SHDEPS_FORCE=1
  [[ "${DOT_QUIET:-0}" -eq 1 ]] && export SHDEPS_QUIET=1

  if _find_shdeps_installer; then
    # shellcheck source=/dev/null
    . "$REPLY" --bootstrap && return 0
  fi

  _warn "  warning: failed to install shdeps — skipping dependency install"
  return 1
}

# Defer shdeps bootstrap until needed — commands like status, diff, push,
# and fetch don't use shdeps and shouldn't pay the startup cost.
_ensure_shdeps() {
  declare -f shdeps_update &>/dev/null && return 0
  _bootstrap_shdeps
}
