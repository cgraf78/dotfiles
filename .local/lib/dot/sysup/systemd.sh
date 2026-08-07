# shellcheck shell=bash
# systemd handling shared by the sysup updaters.
#
# Upgrading a package replaces its binaries on disk but leaves the running
# service on the old code, so an upgrade is not finished until the affected
# units have been restarted and the unit state re-checked.

# Prints the failed-unit table. Returns non-zero when systemd could not be
# queried at all, which the callers must not confuse with "nothing failed".
sysup_failed_units() {
  systemctl --failed --no-legend --plain
}

sysup_report_failed_units() {
  local failed restartable=()

  sysup_log "checking failed systemd units"

  if ! command -v systemctl >/dev/null 2>&1; then
    printf 'skipped: systemctl is not available\n'
    return 0
  fi

  if ! failed="$(sysup_failed_units 2>&1)"; then
    printf '%s\n' "$failed" >&2
    printf '\nerror: could not query systemd for failed units; unit state is unverified\n' >&2
    return 1
  fi

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

  if ! failed="$(sysup_failed_units 2>&1)"; then
    printf '%s\n' "$failed" >&2
    printf 'error: could not query systemd for failed units; restarted nothing\n' >&2
    return 1
  fi

  if [[ -z "$failed" ]]; then
    printf 'ok: no failed units to restart\n'
    return 0
  fi

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

# All active units, not just services: packages ship socket, timer, and path
# units whose stale definitions matter too.
#
# Returns non-zero when the listing could not be obtained. A host with no active
# units and a host whose systemd cannot be reached look identical otherwise, and
# the second must not be reported as "nothing to restart".
sysup_active_units() {
  local units

  units="$(systemctl list-units --state=active --no-legend --plain)" || return

  [[ -n "$units" ]] || return 0
  while read -r unit _; do
    [[ -n "${unit:-}" ]] || continue
    printf '%s\n' "$unit"
  done <<<"$units"
}

# Print the unit names shipped by the given packages. /lib is covered alongside
# /usr/lib because dpkg records the path as the package declared it, which on
# Debian can still be the pre-merged-usr spelling.
#
# A package whose files cannot be listed contributes no units, which would
# silently drop it from the restart set, so say so rather than skipping quietly.
sysup_service_units_for_packages() {
  local pkg file listing

  for pkg in "$@"; do
    if ! listing="$(sysup_backend_package_files "$pkg" 2>&1)"; then
      printf '%s\n' "$listing" >&2
      printf 'warning: could not list files owned by %s; its services will not be restarted\n' \
        "$pkg" >&2
      continue
    fi

    while IFS= read -r file; do
      case "$file" in
        /usr/lib/systemd/system/* | /lib/systemd/system/* | /etc/systemd/system/*)
          # Socket, timer, and path units activate services too, so restarting
          # only *.service leaves activation units running stale definitions.
          case "$file" in
            *.service | *.socket | *.timer | *.path)
              printf '%s\n' "${file##*/}"
              ;;
          esac
          ;;
      esac
    done <<<"$listing"
  done
}

# Intersect the units shipped by the given packages with the units currently
# running, so only services the host actually uses get restarted.
sysup_upgraded_active_service_units() {
  local -a owned_units=()
  local -a active_units=()
  local owned active prefix

  local active_listing suffix

  mapfile -t owned_units < <(sysup_service_units_for_packages "$@")
  ((${#owned_units[@]})) || return 0

  active_listing="$(sysup_active_units)" || return
  [[ -n "$active_listing" ]] || return 0
  mapfile -t active_units <<<"$active_listing"

  for owned in "${owned_units[@]}"; do
    [[ -n "$owned" ]] || continue
    # A template unit ships no runnable instance of its own; its running
    # instances carry the upgraded code.
    if [[ "$owned" == *@.* ]]; then
      prefix="${owned%@.*}"
      suffix=".${owned##*.}"
      for active in "${active_units[@]}"; do
        [[ "$active" == "$prefix@"*"$suffix" ]] && printf '%s\n' "$active"
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
  # A failed reload means the units below would restart against stale in-memory
  # definitions, so the new unit files would not actually be in effect.
  sysup_run_as_root systemctl daemon-reload || return
  # try-restart, not restart: a unit that stopped between the listing and now
  # must not be started back up by an upgrade.
  sysup_run_as_root systemctl try-restart "${units[@]}"
}
