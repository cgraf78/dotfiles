# shellcheck shell=bash
# dot doctor: Installed agent-rule policy checks.

_dr_agent_rules_installed_status() {
  local hook=${DOT_AGENT_RULES_HOOK:-$DOT_EXTENSIONS_DIR/merge-hooks.d/agent-rules.sh}

  [[ -r "$hook" ]] || return 1
  (
    # Reuse the merge hook's source-selection and provider boundary so doctor
    # cannot silently drift into a second policy renderer. A Dot without the
    # public hook runtime cannot answer at all; say so with its own status.
    _dr_hook_runtime_source || exit 3
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
    elif [[ "$status" -eq 3 && -z "$reason" ]]; then
      _dr_skip "generated policy check skipped" \
        "this dot has no public hook runtime; run 'dot update' to upgrade it"
    else
      case "$reason" in
        manifest-missing)
          _dr_hint_row fail "generated policy manifest is missing" "" "run 'dot update -f'"
          ;;
        manifest-mismatch)
          _dr_hint_row fail "generated policy manifest is stale" "" "run 'dot update -f'"
          ;;
        manifest-mode | target-mode)
          _dr_hint_row fail "generated policy permissions are unsafe${detail:+: $detail}" "" \
            "run 'dot update -f'"
          ;;
        target-missing)
          _dr_hint_row fail "generated policy target is missing: $detail" "" "run 'dot update -f'"
          ;;
        target-mismatch)
          _dr_hint_row fail "generated policy target was modified: $detail" "" "run 'dot update -f'"
          ;;
        source-selection-failed)
          _dr_hint_row fail "agent rule source selection failed" "" \
            "check ~/.config/dot/merge-hooks.d/agent-rules and the overlay trust inputs, then run 'dot update -f'"
          ;;
        render-failed | render-manifest-failed | render-block-invalid | render-normalization-failed)
          _dr_hint_row fail "agent rule validation render failed" "" \
            "run 'dot update -f' to see the agent-rules-sync error"
          ;;
        target-block-invalid)
          _dr_hint_row fail "generated policy target has a malformed managed block: $detail" "" \
            "run 'dot update -f'"
          ;;
        '')
          # Nothing came back: the hook runtime or the hook did not load.
          _dr_hint_row fail "agent rule validation could not run" \
            "the agent-rules merge hook did not load" "run 'dot update -f' and retry"
          ;;
        *)
          _dr_hint_row fail "agent rule validation failed: $reason" "" \
            "run 'dot update -f' to regenerate, and report the reason if it persists"
          ;;
      esac
    fi
  fi
}
