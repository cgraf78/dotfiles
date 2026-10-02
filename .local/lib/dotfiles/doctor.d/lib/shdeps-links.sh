# shellcheck shell=bash
# dot doctor: shared shdeps-backed command-link checks.
#
# Overlay-facing contract (stable; see doctor.d/README.md):
#
#   dot_doctor_source doctor.d/lib/shdeps-links.sh || return
#   _dr_check_shdeps_bin_group <fail|warn> <dependency>
#
# Checks the public command links shdeps reports for cgraf78/<dependency>
# (`shdeps dep-links`). When the installed shdeps provides `shdeps health`,
# the base Tools section already reports every installed package's links
# from that one stat-only pass, so this call is a silent no-op: overlays keep
# calling it with their dependency list and never duplicate a row or need to
# know which mode is active. With an older shdeps it performs the per-group
# check: one ok row per group, or a row per problem at the given severity.
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
# command, so the per-group checks below can stand down.
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

_dr_shdeps_link_issue() {
  local level="$1" label="$2" detail="${3:-}"

  if [[ "$level" == "fail" ]]; then
    _dr_fail "$label" "$detail"
  else
    _dr_warn "$label" "$detail"
  fi
}

_dr_check_shdeps_bin_group() {
  local level="$1" dependency="$2"

  # shdeps health covers this group (and every other package) in the base
  # Tools row; reporting it again here would only duplicate rows.
  _dr_shdeps_health_probe && return 0

  local rows shdeps_conf_dir
  _dot_shdeps_conf_dir
  shdeps_conf_dir="$REPLY"
  if ! rows=$(SHDEPS_CONF_DIR="$shdeps_conf_dir" \
    command shdeps dep-links "cgraf78/$dependency" 2>/dev/null); then
    _dr_shdeps_link_issue "$level" "$dependency bin links unchecked" \
      "shdeps cannot resolve command links for cgraf78/$dependency; run 'dot update'"
    return 0
  fi

  if [[ -z "$rows" ]]; then
    _dr_shdeps_link_issue "$level" "$dependency bin links missing" \
      "shdeps reported no public command links for cgraf78/$dependency; run 'dot update'"
    return 0
  fi

  local cmd link expected extra actual
  local issue_count=0 command_count=0

  # shdeps owns the vocabulary of commands and expected targets. Dot doctor
  # only verifies that the live public command path still matches that contract.
  while IFS=$'\t' read -r cmd link expected extra || [[ -n "$cmd$link$expected$extra" ]]; do
    if [[ -z "$cmd" || -z "$link" || -z "$expected" || -n "$extra" ]]; then
      ((issue_count++)) || true
      _dr_shdeps_link_issue "$level" "$dependency bin links malformed" \
        "unexpected shdeps dep-links row for cgraf78/$dependency"
      continue
    fi

    ((command_count++)) || true

    if [[ ! -e "$link" && ! -L "$link" ]]; then
      ((issue_count++)) || true
      _dr_shdeps_link_issue "$level" "$cmd not linked" \
        "expected $(_dr_tilde "$link") -> $(_dr_tilde "$expected"); run 'dot update'"
      continue
    fi

    if [[ "$link" != "$expected" ]]; then
      if [[ ! -L "$link" ]]; then
        ((issue_count++)) || true
        _dr_shdeps_link_issue "$level" "$cmd not linked" \
          "expected $(_dr_tilde "$link") -> $(_dr_tilde "$expected"); run 'dot update'"
        continue
      fi

      if ! _dr_symlink_points_to "$link" "$expected"; then
        ((issue_count++)) || true
        actual=$(_dr_symlink_target_path "$link" 2>/dev/null || echo "?")
        _dr_shdeps_link_issue "$level" "$cmd link target drift" \
          "got $(_dr_tilde "$actual"), expected $(_dr_tilde "$expected"); run 'dot update'"
        continue
      fi
    fi

    if [[ ! -x "$link" ]]; then
      ((issue_count++)) || true
      _dr_shdeps_link_issue "$level" "$cmd not executable" "$(_dr_tilde "$link")"
    fi
  done <<<"$rows"

  if [[ "$issue_count" -eq 0 ]]; then
    _dr_ok "$dependency bin links" "$command_count command(s)"
  fi
}
