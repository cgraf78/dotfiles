# shellcheck shell=bash
# dot doctor: Installed agent-rule policy checks.

_dr_agent_rules_installed_status() {
  local hook=${DOT_AGENT_RULES_HOOK:-$DOT_EXTENSIONS_DIR/merge-hooks.d/agent-rules.sh}

  [[ -r "$hook" ]] || return 1
  (
    # Reuse the merge hook's source-selection and provider boundary so doctor
    # cannot silently drift into a second policy renderer.
    # shellcheck source=/dev/null
    . "$DOT_SOURCE_ROOT/lib/dot/public/xdg.sh" || exit 1
    # shellcheck source=/dev/null
    . "$DOT_SOURCE_ROOT/lib/dot/log.sh" || exit 1
    # shellcheck source=/dev/null
    . "$DOT_SOURCE_ROOT/lib/dot/temp.sh" || exit 1
    # shellcheck source=/dev/null
    . "$DOT_SOURCE_ROOT/lib/dot/merge-block.sh" || exit 1
    # shellcheck source=/dev/null
    . "$DOT_SOURCE_ROOT/lib/dot/families.sh" || exit 1
    # shellcheck source=/dev/null
    . "$DOT_SOURCE_ROOT/lib/dot/merge-hooks.sh" || exit 1
    # shellcheck source=/dev/null
    . "$DOT_SOURCE_ROOT/lib/dot/extension-trust.sh" || exit 1
    # shellcheck source=/dev/null
    . "$DOT_SOURCE_ROOT/lib/dot/hook-api.sh" || exit 1
    # shellcheck source=/dev/null
    . "$hook" || exit 1
    _dot_agent_rules_check_installed
    status=$?
    printf '%s\n' "$REPLY"
    exit "$status"
  )
}

_dr_check_agent_rules() {
  local account_home

  _dr_section "Agent rules"

  if [[ "${DOT_TEST:-0}" == 1 && "${DOT_TEST_AGENT_RULES_CHECK:-0}" != 1 ]]; then
    _dr_skip "generated policy check skipped in isolated tests"
  elif [[ "${DOT_TEST_AGENT_RULES_CHECK:-0}" != 1 ]] && ! _dr_account_home; then
    _dr_skip "generated policy check skipped: account home could not be resolved"
  elif [[ "${DOT_TEST_AGENT_RULES_CHECK:-0}" != 1 ]]; then
    account_home="$REPLY"
    if [[ ! -d "$HOME" || ! "$HOME" -ef "$account_home" ]]; then
      _dr_skip "generated policy check skipped: HOME is not the account home: $HOME"
      return 0
    fi
    _dr_check_agent_rules_installed
  else
    _dr_check_agent_rules_installed
  fi
}

_dr_check_agent_rules_installed() {
  if ! command -v agent-rules-sync >/dev/null 2>&1; then
    _dr_skip "generated policy check skipped: agent-rules-sync not found"
  else
    local result reason detail status
    if result=$(_dr_agent_rules_installed_status); then
      status=0
    else
      status=$?
    fi
    IFS=$'\t' read -r reason detail <<<"$result"
    if [[ "$status" -eq 0 ]]; then
      _dr_ok "generated policy is current"
    else
      case "$reason" in
        manifest-missing)
          _dr_fail "generated policy manifest is missing" "run 'dot update -f'"
          ;;
        manifest-mismatch)
          _dr_fail "generated policy manifest is stale" "run 'dot update -f'"
          ;;
        manifest-mode | target-mode)
          _dr_fail "generated policy permissions are unsafe${detail:+: $detail}" \
            "run 'dot update -f'"
          ;;
        target-missing)
          _dr_fail "generated policy target is missing: $detail" "run 'dot update -f'"
          ;;
        target-mismatch)
          _dr_fail "generated policy target was modified: $detail" "run 'dot update -f'"
          ;;
        source-selection-failed)
          _dr_fail "agent rule source selection failed" "inspect rule and overlay trust inputs"
          ;;
        render-failed | render-manifest-failed | render-block-invalid | render-normalization-failed)
          _dr_fail "agent rule validation render failed" "run agent-rules-sync diagnostics"
          ;;
        target-block-invalid)
          _dr_fail "generated policy target has a malformed managed block: $detail" \
            "run 'dot update -f'"
          ;;
        *)
          _dr_fail "agent rule validation failed: $reason" "inspect dot doctor output"
          ;;
      esac
    fi
  fi
}
