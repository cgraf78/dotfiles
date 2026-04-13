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

_bootstrap_shdeps() {
  local shdeps_lib="" shdeps_dir=""
  # REAL_HOME is set by test framework when HOME is mocked
  local real_home="${REAL_HOME:-$HOME}"

  # Priority: env override > local dev clone > installed clone > fresh install
  if [[ -n "${SHDEPS_LIB:-}" && -f "$SHDEPS_LIB" ]]; then
    shdeps_lib="$SHDEPS_LIB"
  elif [[ -f "$real_home/git/shdeps/shdeps.sh" ]]; then
    shdeps_lib="$real_home/git/shdeps/shdeps.sh"
    shdeps_dir="$real_home/git/shdeps"
  elif [[ -f "$real_home/.local/share/shdeps/shdeps.sh" ]]; then
    shdeps_lib="$real_home/.local/share/shdeps/shdeps.sh"
    shdeps_dir="$real_home/.local/share/shdeps"
  else
    _log "  shdeps not found, installing..."
    local install_url="https://raw.githubusercontent.com/cgraf78/shdeps/main/install.sh"
    if curl -fsSL "$install_url" | bash &>/dev/null; then
      shdeps_lib="$HOME/.local/share/shdeps/shdeps.sh"
      shdeps_dir="$HOME/.local/share/shdeps"
    else
      _warn "  warning: failed to install shdeps — skipping dependency install"
      return 1
    fi
  fi

  # Ensure the CLI is symlinked into PATH (install.sh handles this for
  # installed clones, but dev clones at ~/git/shdeps skip install.sh).
  if [[ -n "$shdeps_dir" && -x "$shdeps_dir/bin/shdeps" ]]; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$shdeps_dir/bin/shdeps" "$HOME/.local/bin/shdeps"
  fi

  # Map dotfiles env vars to shdeps config
  export SHDEPS_CONF_DIR="$HOME/.config/shdeps"
  export SHDEPS_HOOKS_DIR="$HOME/.config/shdeps/hooks.d"
  export SHDEPS_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dot/deps"
  [[ "${DOT_FORCE:-0}" -eq 1 ]] && export SHDEPS_FORCE=1
  [[ "${DOT_QUIET:-0}" -eq 1 ]] && export SHDEPS_QUIET=1

  # shellcheck source=/dev/null
  . "$shdeps_lib" || {
    _warn "  warning: failed to source $shdeps_lib"
    return 1
  }

  # Self-update shdeps clone (TTL-cached, skips dirty clones).
  # Done directly via git pull instead of `shdeps self-update` to avoid
  # a chicken-and-egg problem: installed versions that predate the
  # self-update command can't run it to get the update.
  # Use shdeps's default state dir (not dot's) so the TTL stamp is
  # shared with standalone `shdeps self-update` calls.
  if [[ -n "$shdeps_dir" && -d "$shdeps_dir/.git" ]] &&
    declare -f _shdeps_remote_stamp &>/dev/null; then
    local _su_saved="$SHDEPS_STATE_DIR"
    SHDEPS_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/shdeps"
    local _su_stamp
    _su_stamp=$(_shdeps_remote_stamp "shdeps" "self-update")
    if ! _shdeps_remote_fresh "$_su_stamp" &&
      [[ -z "$(git -C "$shdeps_dir" status --porcelain --untracked-files=normal 2>/dev/null)" ]]; then
      git -C "$shdeps_dir" pull --ff-only --quiet 2>/dev/null || true
      _shdeps_remote_touch "$_su_stamp" 2>/dev/null || true
    fi
    SHDEPS_STATE_DIR="$_su_saved"
  fi
}

# Defer shdeps bootstrap until needed — commands like status, diff, push,
# and fetch don't use shdeps and shouldn't pay the startup cost.
_ensure_shdeps() {
  declare -f shdeps_update &>/dev/null && return 0
  _bootstrap_shdeps
}
