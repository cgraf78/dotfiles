# shellcheck shell=bash
# dot doctor: Cron checks.
#
# Core already reports whether the last cron `dot update` succeeded. This
# section checks what cron will actually run: the managed block in the user
# crontab must match what the cron merge hook renders for this host now, and
# a crontab-wide SHELL= must name an executable, because cron runs every job
# through it.

# Print what the cron merge hook would do for this host: its block marker
# on the first line, then `none` when there is no tracked source at all (the
# hook then leaves the crontab alone) or `block`, followed by the managed
# block it would install (nothing when no tracked entry applies here). Fails
# when the hook runtime or the hook cannot load. Runs the real hook renderer
# in a subshell; its warnings (for example an over-long PATH) belong to
# `dot update`, so stderr is dropped here.
_dr_cron_expected_block() {
  local hook=$DOT_EXTENSIONS_DIR/merge-hooks.d/cron.sh

  [[ -r $hook ]] || return 1
  (
    _dr_hook_runtime_source || exit 1
    # shellcheck source=/dev/null
    . "$hook" || exit 1
    local -a _cron_sources
    _cron_source_files
    if ((${#_cron_sources[@]} == 0)); then
      printf '%s\nnone\n' "$_CRON_MARKER"
      exit 0
    fi
    _cron_render_block
    printf '%s\nblock\n%s' "$_CRON_MARKER" "$REPLY"
  ) 2>/dev/null
}

# Check every crontab-wide SHELL= line in $1. Cron strips one level of
# quotes and expands nothing, so the value must be an absolute executable.
_dr_cron_check_shell() {
  local line value
  while IFS= read -r line; do
    [[ $line =~ ^[[:space:]]*SHELL[[:space:]]*=[[:space:]]*(.*[^[:space:]])[[:space:]]*$ ]] || continue
    value=${BASH_REMATCH[1]}
    case $value in
      \"*\" | \'*\') value=${value:1:${#value}-2} ;;
    esac
    # Display text must stay on one record line.
    value=${value//[$'\t\r']/ }
    if [[ $value != /* ]]; then
      _dr_fail "cron SHELL is not an absolute path: $value" \
        "cron needs an absolute program path; fix the SHELL= line, then run 'dot update'"
    elif [[ -x $value && ! -d $value ]]; then
      _dr_ok "cron SHELL is executable" "$(_dr_tilde "$value")"
    else
      _dr_fail "cron SHELL is not executable: $(_dr_tilde "$value")" \
        "every cron job using it fails; restore the program or run 'dot update'"
    fi
  done <<<"$1"
}

_dr_check_cron() {
  _dr_section "Cron"

  if [[ ! -d "$(_merge_hook_family cron/cron.d)" ]]; then
    _dr_skip "no tracked cron entries to check"
    return 0
  fi

  local crontab_out crontab_command expected='' marker='' mode='' log
  log=${XDG_STATE_HOME:-$HOME/.local/state}/dot/update.log
  if expected=$(_dr_cron_expected_block); then
    marker=${expected%%$'\n'*}
    expected=${expected#*$'\n'}
    mode=${expected%%$'\n'*}
    expected=${expected#"$mode"}
    expected=${expected#$'\n'}
  fi

  # The merge hook quietly does nothing without crontab, so tracked jobs
  # that apply here would never run; say so instead of skipping.
  if [[ "${DOT_TEST:-0}" != 1 ]] && ! command -v crontab >/dev/null 2>&1; then
    if [[ -n $expected || -z $marker ]]; then
      _dr_warn "crontab not found" \
        "tracked cron entries cannot be installed; install cron, then run 'dot update'"
    else
      _dr_skip "crontab not found" "no tracked cron entry applies to this host"
    fi
    return 0
  fi
  _dr_account_scoped_command \
    "Cron" crontab "${DOT_TEST_CRONTAB:-}" || return 0
  crontab_command="$REPLY"
  crontab_out=$("$crontab_command" -l 2>/dev/null || echo "")

  if [[ -z $marker || -z $mode ]]; then
    _dr_skip "managed cron block unchecked" "the cron merge hook could not load"
  elif [[ -z $expected ]]; then
    if [[ $crontab_out != *"$marker begin"* ]]; then
      _dr_ok "no tracked cron entries apply to this host"
    elif [[ $mode == none ]]; then
      # With no tracked source at all the hook leaves the crontab alone.
      _dr_warn "managed cron block is stale" \
        "no tracked cron source remains, and dot update keeps the old block; remove it with 'crontab -e'"
    else
      _dr_warn "managed cron block is stale" \
        "no tracked entry applies to this host any more; run 'dot update' to remove it"
    fi
  elif [[ $crontab_out == *"$expected"* ]]; then
    _dr_ok "managed cron block is current"
  elif [[ $crontab_out == *"$marker begin"* ]]; then
    _dr_warn "managed cron block is stale" \
      "it differs from the tracked entries; run 'dot update', and check $(_dr_tilde "$log") if cron updates keep failing"
  else
    _dr_warn "managed cron block missing" \
      "tracked entries are not installed; run 'dot update', and check $(_dr_tilde "$log") if cron updates keep failing"
  fi

  _dr_cron_check_shell "$crontab_out"
}
