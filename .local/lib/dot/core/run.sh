# shellcheck shell=bash
# Command execution helpers with quiet logging and live UI ticks.

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

_run_to_log_with_ticks() {
  local log="$1"
  shift

  if ! _ui_live_enabled; then
    "$@" >"$log" 2>&1
    return $?
  fi

  local tmpdir="" status_file="" child rc=0
  if ! tmpdir=$(mktemp -d 2>/dev/null); then
    "$@" >"$log" 2>&1
    return $?
  fi
  status_file="$tmpdir/status"

  (
    "$@" >"$log" 2>&1
    printf '%s' "$?" >"$status_file"
  ) &
  child=$!

  while [[ ! -s "$status_file" ]]; do
    if ! kill -0 "$child" 2>/dev/null; then
      break
    fi
    _ui_stage_tick
    sleep "${DOT_UI_TICK_SECONDS:-0.2}"
  done

  wait "$child" 2>/dev/null || true
  rc=$(cat "$status_file" 2>/dev/null || printf '1')
  rm -rf "$tmpdir"
  return "$rc"
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

  if _run_to_log_with_ticks "$log" "$@"; then
    rm -f "$log"
    return 0
  fi

  _logfile_print "$label" "$log"
  rm -f "$log"
  _warn "  warning: $warning"
  return 0
}
