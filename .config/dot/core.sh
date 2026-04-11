# shellcheck shell=bash
# Core constants and logging helpers for dot and dotbootstrap.

DOTFILES="$HOME/.dotfiles"
# shellcheck disable=SC2034  # used by scripts that source this file
GIT="git --git-dir=$DOTFILES --work-tree=$HOME"
# shellcheck disable=SC2034  # used by scripts that source this file
WORK_DIR="$HOME/.dotfiles-work"

# Quiet mode — suppresses non-essential output. Set by `dot update --cron`.
DOT_QUIET="${DOT_QUIET:-0}"

# ---------------------------------------------------------------------------
# Colors — disabled when not a terminal or NO_COLOR is set.
# ---------------------------------------------------------------------------

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  _C_RESET=$'\033[0m'
  _C_BOLD=$'\033[1m'
  _C_DIM=$'\033[2m'
  _C_GREEN=$'\033[32m'
  _C_YELLOW=$'\033[33m'
  _C_WHITE=$'\033[38;2;255;255;255m'
else
  _C_RESET="" _C_BOLD="" _C_DIM="" _C_GREEN="" _C_YELLOW="" _C_WHITE=""
fi

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

# Print a message unless quiet mode is active.
_log() {
  [[ "$DOT_QUIET" -eq 1 ]] || echo "$@"
}

# Section header (bright bold white, always prints).
_header() {
  echo "${_C_BOLD}${_C_WHITE}$*${_C_RESET}"
}

# Section header (bright bold white, respects quiet mode).
_log_header() {
  [[ "$DOT_QUIET" -eq 1 ]] || echo "${_C_BOLD}${_C_WHITE}$*${_C_RESET}"
}

# Success message (green, respects quiet mode).
_log_ok() {
  [[ "$DOT_QUIET" -eq 1 ]] || echo "${_C_GREEN}$*${_C_RESET}"
}

# Muted message (dim, respects quiet mode).
_log_dim() {
  [[ "$DOT_QUIET" -eq 1 ]] || echo "${_C_DIM}$*${_C_RESET}"
}

# Warning message (yellow, always prints to stderr).
_warn() {
  echo "${_C_YELLOW}$*${_C_RESET}" >&2
}

_logfile_create() {
  local log=""
  if ! log=$(mktemp 2>/dev/null); then
    REPLY=""
    return 1
  fi
  REPLY="$log"
}

_logfile_print() {
  local label="$1"
  local log="$2"
  [[ -n "$log" && -s "$log" ]] || return 0
  _warn "  $label output:"
  sed 's/^/    /' "$log" >&2
}

# Run a command, capturing output to the caller's $log if set.
# Returns the command's exit code.
_run_logged() {
  if [[ -n "${log:-}" ]]; then
    "$@" >"$log" 2>&1
  else
    "$@" >/dev/null 2>&1
  fi
}

_run_quiet_logged() {
  local label="$1"
  local warning="$2"
  shift 2

  local log=""
  if ! _logfile_create; then
    "$@" >/dev/null 2>&1 || _warn "  warning: $warning"
    return 0
  fi
  log="$REPLY"

  if "$@" >"$log" 2>&1; then
    rm -f "$log"
    return 0
  fi

  _logfile_print "$label" "$log"
  rm -f "$log"
  _warn "  warning: $warning"
  return 0
}

# ---------------------------------------------------------------------------
# Platform helpers
# ---------------------------------------------------------------------------

_is_wsl() {
  [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSL_INTEROP:-}" ]] && return 0
  [[ -r /proc/sys/kernel/osrelease ]] && grep -qi "microsoft" /proc/sys/kernel/osrelease
}
