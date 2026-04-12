# shellcheck shell=bash
# Shared environment for dot and dotbootstrap.
# Sources all dot modules in dependency order, then bootstraps shdeps.

_dir="${BASH_SOURCE[0]%/*}"
. "$_dir/core.sh"
. "$_dir/repos.sh"
. "$_dir/merges.sh"
. "$_dir/cron.sh"

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

# Pull latest shdeps if the clone is clean and TTL has expired.
# Dirty local clones (active development) are left alone.
# $1=shdeps git directory
_shdeps_self_update() {
  local dir="$1"
  local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/dot/deps"
  local stamp="$state_dir/shdeps.self-update.stamp"
  local ttl="${SHDEPS_REMOTE_TTL:-3600}"

  # Skip if forced (shdeps_update handles force for deps, not self)
  # Check TTL: skip pull if stamp is fresh
  if [[ -f "$stamp" ]]; then
    local cached="" now=""
    read -r cached <"$stamp" 2>/dev/null || cached=0
    now=$(date +%s 2>/dev/null || echo 0)
    if [[ "$cached" =~ ^[0-9]+$ && "$now" =~ ^[0-9]+$ ]]; then
      if (( now - cached < ttl )); then
        return 0
      fi
    fi
  fi

  # Skip if dirty (uncommitted changes = active development)
  if [[ -n "$(git -C "$dir" status --porcelain --untracked-files=normal 2>/dev/null)" ]]; then
    return 0
  fi

  # Pull latest
  if git -C "$dir" pull --ff-only --quiet 2>/dev/null; then
    mkdir -p "$state_dir"
    date +%s >"$stamp"
  fi
}

_bootstrap_shdeps() {
  local shdeps_lib="" shdeps_dir=""
  # REAL_HOME is set by test framework when HOME is mocked
  local real_home="${REAL_HOME:-$HOME}"

  # Priority: env override > local dev clone > installed clone > fresh clone
  if [[ -n "${SHDEPS_LIB:-}" && -f "$SHDEPS_LIB" ]]; then
    shdeps_lib="$SHDEPS_LIB"
  elif [[ -f "$real_home/git/shdeps/shdeps.sh" ]]; then
    shdeps_lib="$real_home/git/shdeps/shdeps.sh"
    shdeps_dir="$real_home/git/shdeps"
  elif [[ -f "$real_home/.local/share/shdeps/shdeps.sh" ]]; then
    shdeps_lib="$real_home/.local/share/shdeps/shdeps.sh"
    shdeps_dir="$real_home/.local/share/shdeps"
  elif [[ -f "$HOME/.local/share/shdeps/shdeps.sh" ]]; then
    shdeps_lib="$HOME/.local/share/shdeps/shdeps.sh"
    shdeps_dir="$HOME/.local/share/shdeps"
  else
    _log "  shdeps not found, cloning..."
    if git clone --depth 1 https://github.com/cgraf78/shdeps.git \
      "$HOME/.local/share/shdeps" &>/dev/null; then
      shdeps_lib="$HOME/.local/share/shdeps/shdeps.sh"
      shdeps_dir="$HOME/.local/share/shdeps"
    else
      _warn "  warning: failed to clone shdeps — skipping dependency install"
      return 1
    fi
  fi

  # Self-update: pull latest shdeps before sourcing.
  # Uses same TTL cache and dirty-skip policy as shdeps's own git method.
  if [[ -n "$shdeps_dir" && -d "$shdeps_dir/.git" ]]; then
    _shdeps_self_update "$shdeps_dir"
  fi

  # Map dotfiles env vars to shdeps config
  export SHDEPS_CONF="$HOME/.config/dot/deps.conf"
  export SHDEPS_HOOKS_DIR="$HOME/.config/dot/deps-hooks.d"
  # Keep existing state dir for cache continuity
  export SHDEPS_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dot/deps"
  [[ "${DOT_FORCE:-0}" -eq 1 ]] && export SHDEPS_FORCE=1
  [[ "${DOT_QUIET:-0}" -eq 1 ]] && export SHDEPS_QUIET=1

  # shellcheck source=/dev/null
  . "$shdeps_lib" || {
    _warn "  warning: failed to source $shdeps_lib"
    return 1
  }

  # Compat aliases so existing hooks can use old names unchanged.
  # Hooks reference _PKG_MGR, _dep_hook_due, _require_sudo, _is_wsl.
  # _is_wsl and _require_sudo are still in core.sh. _dep_hook_due and
  # _PKG_MGR need aliases from shdeps equivalents.
}

_bootstrap_shdeps
