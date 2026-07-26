# shellcheck shell=bash
# dot doctor: Merges checks.

_dr_check_merges() {
  _dr_section "Config merges"

  local hooks_dir
  hooks_dir="$(_merge_hook_dir)"
  if [[ ! -d "$hooks_dir" ]]; then
    _dr_fail "merge-hooks.d/ missing" "$(_dr_tilde "$hooks_dir")"
    return 0
  fi

  local hook_count
  hook_count=$(_merge_hook_specs | wc -l | tr -d ' ')
  if [[ "$hook_count" -gt 0 ]]; then
    _dr_ok "merge-hooks.d/" "$hook_count hook(s)"
  else
    _dr_warn "merge-hooks.d/ exists but no merge hooks found"
  fi

  local output_specs=(
    "Claude settings|$HOME/.claude/settings.json"
    "Codex config|$HOME/.codex/config.toml"
    "Gemini settings|$HOME/.gemini/settings.json"
    "SSH config|$DOT_SSH_CONFIG"
  )
  local checked_count=0 symlink_count=0 spec path
  for spec in "${output_specs[@]}"; do
    IFS='|' read -r _ path <<<"$spec"
    [[ -e "$path" || -L "$path" ]] || continue
    ((checked_count++)) || true
    if [[ -L "$path" ]]; then
      ((symlink_count++)) || true
    fi
  done

  if [[ "$symlink_count" -gt 0 ]]; then
    _dr_warn "$symlink_count merge-managed config output symlink(s)" \
      "run 'dot update' to rebuild generated config files"
  elif [[ "$checked_count" -gt 0 ]]; then
    _dr_ok "merge-managed config outputs" "$checked_count checked"
  else
    _dr_skip "merge-managed config outputs" "none present"
  fi
}
