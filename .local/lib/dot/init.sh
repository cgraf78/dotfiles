# shellcheck shell=bash
# Shared environment for dot and dotbootstrap.
# Sources all dot modules in dependency order, then bootstraps shdeps.

_dir="${BASH_SOURCE[0]%/*}"
. "$_dir/core.sh"
. "$_dir/merge-block.sh"
. "$_dir/repos.sh"
. "$_dir/merges.sh"

# ---------------------------------------------------------------------------
# shdeps bootstrap — find or clone shdeps, configure for dotfiles
# ---------------------------------------------------------------------------

# Locate install.sh: env override → dev clone → installed clone → curl install.
# Sets REPLY to the path on success, returns 1 if not found.
# Also exports SHDEPS_LIB so _bootstrap skips its own redundant discovery.
_find_shdeps_installer() {
  # REAL_HOME is set by test framework when HOME is mocked
  local real_home="${REAL_HOME:-$HOME}"
  local dev_dir="${SHDEPS_GIT_DEV_DIR:-$real_home/git}"

  if [[ -n "${SHDEPS_LIB:-}" && -f "${SHDEPS_LIB%/*}/install.sh" ]]; then
    REPLY="${SHDEPS_LIB%/*}/install.sh"
    return 0
  fi
  if [[ -f "$dev_dir/shdeps/shdeps.sh" ]]; then
    export SHDEPS_LIB="$dev_dir/shdeps/shdeps.sh"
    REPLY="$dev_dir/shdeps/install.sh"
    return 0
  fi
  if [[ -f "$real_home/.local/share/shdeps/shdeps.sh" ]]; then
    export SHDEPS_LIB="$real_home/.local/share/shdeps/shdeps.sh"
    REPLY="$real_home/.local/share/shdeps/install.sh"
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
  # Enable EPEL on dnf systems — many dotfiles deps need it.
  # User can override with SHDEPS_AUTO_EPEL=0 in their environment.
  export SHDEPS_AUTO_EPEL="${SHDEPS_AUTO_EPEL:-1}"
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
