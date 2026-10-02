# shellcheck shell=bash
# dot doctor: Tools checks.
#
# Core reports the Git and Bash runtimes and the dependency provider itself;
# this section covers what base adds on top: the shdeps configuration and
# the health of everything shdeps installed.

dot_doctor_source doctor.d/lib/shdeps-links.sh || return

# Render `shdeps health` as one row: ok when healthy, otherwise the worst
# severity it reported with the first few problems and the command that
# lists them all. Only the severity column drives the verdict; the other
# columns are display text, and unknown kinds render like any other.
_dr_check_shdeps_health() {
  local severity package kind path detail sample level=warn count=0
  local -a samples=()

  case $_DR_SHDEPS_HEALTH_STATUS in
    0)
      _dr_ok "shdeps health" "installed dependencies, links, and state are consistent"
      return 0
      ;;
    error-124 | error-137)
      _dr_fail "shdeps health timed out" "run 'shdeps health' to see where it stalls"
      return 0
      ;;
    error-*)
      _dr_fail "shdeps health failed (exit ${_DR_SHDEPS_HEALTH_STATUS#error-})" \
        "run 'shdeps health' to see the error"
      return 0
      ;;
  esac

  while IFS=$'\t' read -r severity package kind path detail; do
    [[ -n $severity ]] || continue
    count=$((count + 1))
    if [[ $severity == fail ]]; then
      level=fail
    fi
    if ((${#samples[@]} < 3)); then
      sample="${package:--}: $kind"
      [[ -z $path || $path == - ]] || sample+=" $(_dr_tilde "$path")"
      _dr_one_line "$sample"
      samples+=("$REPLY")
    fi
  done <<<"$_DR_SHDEPS_HEALTH_OUTPUT"
  # An incomplete report fails even when every row it managed to print was
  # a warning: the unread state may hide anything.
  if [[ $_DR_SHDEPS_HEALTH_STATUS == 3 ]]; then
    level=fail
  fi

  if ((count == 0)); then
    _dr_fail "shdeps health report incomplete" "run 'shdeps health' to see what it could not read"
    return 0
  fi
  sample=
  for detail in "${samples[@]}"; do
    sample+=${sample:+; }$detail
  done
  if ((count > ${#samples[@]})); then
    sample+="; and $((count - ${#samples[@]})) more"
  fi
  if [[ $level == fail ]]; then
    _dr_fail "shdeps health: $count problem(s)" \
      "$sample; run 'shdeps health' for details and fixes"
  else
    _dr_warn "shdeps health: $count problem(s)" \
      "$sample; run 'shdeps health' for details, then 'dot update'"
  fi
}

_dr_check_tools() {
  _dr_section "Tools"

  # curl — used by shdeps bootstrap and github:release installs
  if command -v curl >/dev/null 2>&1; then
    _dr_ok "curl" "$(curl --version 2>/dev/null | awk 'NR==1 {print $2; exit}')"
  else
    _dr_warn "curl missing" "needed to bootstrap shdeps and install github:release deps"
  fi

  # shdeps config
  local shdeps_conf_dir
  _dot_shdeps_conf_dir
  shdeps_conf_dir="$REPLY"
  if [[ -d "$shdeps_conf_dir" ]]; then
    # Count through a glob: managed .conf files are usually overlay
    # symlinks, which `find -type f` silently skipped. `-f` follows links
    # and rejects dangling ones, matching what shdeps can actually read.
    local conf_count=0 conf
    for conf in "$shdeps_conf_dir"/*.conf; do
      [[ -f $conf ]] && conf_count=$((conf_count + 1))
    done
    if [[ "$conf_count" -gt 0 ]]; then
      _dr_ok "shdeps config" "$conf_count .conf file(s)"
    else
      _dr_warn "shdeps config dir exists but no .conf files" \
        "$(_dr_tilde "$shdeps_conf_dir"); restore the tracked .conf files, then run 'dot update'"
    fi
  else
    _dr_warn "shdeps config dir missing" \
      "$(_dr_tilde "$shdeps_conf_dir"); restore it from the base checkout, then run 'dot update'"
  fi

  if ! command -v shdeps >/dev/null 2>&1; then
    _dr_warn "dependency command links unchecked" "shdeps is not on PATH; run 'dot update'"
  elif _dr_shdeps_health_probe; then
    # One stat-only pass covers every installed package's command links
    # plus deferred, recovery, and install-root state.
    _dr_check_shdeps_health
  else
    # An older shdeps without `health`: check the always-active providers
    # (shell, terminal, and rule policy) one group at a time, as before.
    _dr_check_shdeps_bin_group fail agent-rules-sync
    _dr_check_shdeps_bin_group warn termnav
    _dr_check_shdeps_bin_group warn tmux-tools
    _dr_check_shdeps_bin_group warn ds
  fi
}
