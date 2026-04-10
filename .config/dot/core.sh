#!/bin/bash
# Core constants and logging helpers for dot and dotbootstrap.

DOTFILES="$HOME/.dotfiles"
# shellcheck disable=SC2034  # used by scripts that source this file
GIT="git --git-dir=$DOTFILES --work-tree=$HOME"
# shellcheck disable=SC2034  # used by scripts that source this file
WORK_DIR="$HOME/.dotfiles-work"

# Quiet mode — suppresses non-essential output. Set by `dot update --cron`.
DOT_QUIET="${DOT_QUIET:-0}"

# Print a message unless quiet mode is active.
_log() {
  [[ "$DOT_QUIET" -eq 1 ]] || echo "$@"
}

# Print a message to stderr regardless of quiet mode.
_warn() {
  echo "$@" >&2
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
