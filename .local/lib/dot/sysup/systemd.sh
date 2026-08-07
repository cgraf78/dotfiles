# shellcheck shell=bash
# systemd handling shared by the sysup updaters.
#
# Upgrading a package replaces its binaries on disk but leaves the running
# service on the old code, so an upgrade is not finished until the affected
# units have been restarted and the unit state re-checked.

sysup_failed_units() {
  command -v systemctl >/dev/null 2>&1 || return 0
  systemctl --failed --no-legend --plain 2>/dev/null || true
}

sysup_report_failed_units() {
  local failed restartable=()

  sysup_log "checking failed systemd units"

  if ! command -v systemctl >/dev/null 2>&1; then
    printf 'skipped: systemctl is not available\n'
    return 0
  fi

  failed="$(sysup_failed_units)"

  if [[ -z "$failed" ]]; then
    printf 'ok: no failed systemd units\n'
    return 0
  fi

  printf '%s\n' "$failed"
  while read -r unit _; do
    [[ -n "${unit:-}" ]] || continue
    [[ "$(systemctl is-enabled "$unit" 2>/dev/null || true)" == "enabled" ]] || continue
    restartable+=("$unit")
  done <<<"$failed"

  if ((${#restartable[@]})); then
    printf '\nhint: run: %s --restart-failed\n' "${SYSUP_BACKEND_NAME:-sysup}" >&2
    printf 'hint: failed enabled units: %s\n' "${restartable[*]}" >&2
  fi

  printf '\nerror: systemd has failed units\n' >&2
  return 1
}

# Restart failed units that are enabled. Disabled units are left alone: they
# failed on a manual or dependency-triggered start, and restarting them here
# would start services the host is not configured to run.
sysup_restart_failed_units() {
  local failed unit state
  local units=()

  if ! command -v systemctl >/dev/null 2>&1; then
    printf 'skipped: systemctl is not available\n'
    return 0
  fi

  failed="$(sysup_failed_units)"
  [[ -n "$failed" ]] || return 0

  while read -r unit _; do
    [[ -n "${unit:-}" ]] || continue
    state="$(systemctl is-enabled "$unit" 2>/dev/null || true)"
    [[ "$state" == "enabled" ]] || continue
    units+=("$unit")
  done <<<"$failed"

  if ((${#units[@]} == 0)); then
    printf 'no failed enabled units to restart\n'
    return 0
  fi

  sysup_log "restarting failed enabled units: ${units[*]}"
  sysup_run_as_root systemctl reset-failed "${units[@]}"
  sysup_run_as_root systemctl restart "${units[@]}"
}

sysup_active_service_units() {
  systemctl list-units --type=service --state=active --no-legend --plain 2>/dev/null |
    while read -r unit _; do
      [[ -n "${unit:-}" ]] || continue
      printf '%s\n' "$unit"
    done
}

# Print the unit names shipped by the given packages. /lib is covered alongside
# /usr/lib because dpkg records the path as the package declared it, which on
# Debian can still be the pre-merged-usr spelling.
sysup_service_units_for_packages() {
  local pkg file

  for pkg in "$@"; do
    while IFS= read -r file; do
      case "$file" in
        /usr/lib/systemd/system/*.service | /lib/systemd/system/*.service | /etc/systemd/system/*.service)
          printf '%s\n' "${file##*/}"
          ;;
      esac
    done < <(sysup_backend_package_files "$pkg" 2>/dev/null)
  done
}

# Intersect the units shipped by the given packages with the units currently
# running, so only services the host actually uses get restarted.
sysup_upgraded_active_service_units() {
  local -a owned_units=()
  local -a active_units=()
  local owned active prefix

  mapfile -t owned_units < <(sysup_service_units_for_packages "$@")
  ((${#owned_units[@]})) || return 0

  mapfile -t active_units < <(sysup_active_service_units)
  ((${#active_units[@]})) || return 0

  for owned in "${owned_units[@]}"; do
    [[ -n "$owned" ]] || continue
    # A template unit ships no runnable service of its own; its running
    # instances carry the upgraded code.
    if [[ "$owned" == *@.service ]]; then
      prefix="${owned%@.service}"
      for active in "${active_units[@]}"; do
        [[ "$active" == "$prefix@"*.service ]] && printf '%s\n' "$active"
      done
      continue
    fi

    for active in "${active_units[@]}"; do
      [[ "$active" == "$owned" ]] && printf '%s\n' "$active"
    done
  done | sort -u
}

sysup_restart_upgraded_services() {
  local -a units=()

  if (($# == 0)); then
    printf 'ok: no packages upgraded during this run\n'
    return 0
  fi

  if ! command -v systemctl >/dev/null 2>&1; then
    printf 'skipped: systemctl is not available\n'
    return 0
  fi

  mapfile -t units < <(sysup_upgraded_active_service_units "$@")
  if ((${#units[@]} == 0)); then
    printf 'ok: no active services shipped by upgraded packages\n'
    return 0
  fi

  sysup_log "restarting active services from upgraded packages: ${units[*]}"
  sysup_run_as_root systemctl daemon-reload
  # try-restart, not restart: a unit that stopped between the listing and now
  # must not be started back up by an upgrade.
  sysup_run_as_root systemctl try-restart "${units[@]}"
}
