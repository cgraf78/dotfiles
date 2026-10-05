# shellcheck shell=bash
# dot doctor: shared `shdeps health` probe for the base Tools section.
#
# Loads doctor.d/lib/compat.sh itself, so callers need nothing else.

dot_doctor_source doctor.d/lib/compat.sh || return

# Probe `shdeps health` once per worker and cache the verdict in
# _DR_SHDEPS_HEALTH_STATUS:
#   0            healthy (no rows)
#   1            problems (rows in _DR_SHDEPS_HEALTH_OUTPUT)
#   3            report incomplete: unreadable state or a write failure;
#                rows still list what was found, including a fail row
#   unsupported  no shdeps, or an older one that rejects the command
#                (usage error 2) or cannot run it (127)
#   any other    the command exists but failed (a crash, a timeout, or 1
#                with no rows); the Tools row reports it as an error
# Rows are TAB-separated: severity (fail|warn), package, kind, path, detail.
# Each extension runs in its own worker, so every worker pays one stat-only
# shdeps process at most. Succeeds when the installed shdeps has the
# command.
# Seconds `shdeps health` may take before it is reported as timed out.
_DR_SHDEPS_HEALTH_DEADLINE=15

_dr_shdeps_health_probe() {
  local conf_dir output shdeps_bin status=0

  if [[ -z ${_DR_SHDEPS_HEALTH_STATUS:-} ]]; then
    _DR_SHDEPS_HEALTH_STATUS=unsupported
    _DR_SHDEPS_HEALTH_OUTPUT=
    if shdeps_bin=$(type -P shdeps 2>/dev/null) && [[ -n $shdeps_bin ]]; then
      # The default config dir follows XDG_CONFIG_HOME, and a missing one
      # reports healthy; name the dotfiles-owned one explicitly.
      _dot_shdeps_conf_dir
      conf_dir=$REPLY
      # The command is stat-only, but a hung filesystem must not hold the
      # whole doctor run.
      output=$(SHDEPS_CONF_DIR="$conf_dir" \
        _dr_run_bounded "$_DR_SHDEPS_HEALTH_DEADLINE" "$shdeps_bin" health \
        </dev/null 2>/dev/null) || status=$?
      case $status in
        2 | 127) ;;
        1)
          # Problems without a single row is not a healthy answer.
          if [[ -n $output ]]; then
            _DR_SHDEPS_HEALTH_STATUS=1
          else
            _DR_SHDEPS_HEALTH_STATUS=error-1
          fi
          ;;
        0 | 3) _DR_SHDEPS_HEALTH_STATUS=$status ;;
        *) _DR_SHDEPS_HEALTH_STATUS=error-$status ;;
      esac
      _DR_SHDEPS_HEALTH_OUTPUT=$output
    fi
  fi
  [[ $_DR_SHDEPS_HEALTH_STATUS != unsupported ]]
}
