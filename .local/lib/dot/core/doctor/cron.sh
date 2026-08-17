# shellcheck shell=bash
# dot doctor: Cron checks.

_dr_check_cron() {
  _dr_section "Cron"

  if [[ ! -d "$(_merge_hook_family cron/cron.d)" ]]; then
    _dr_skip "no tracked cron entries to check"
    return 0
  fi

  local crontab_out
  crontab_out=$(crontab -l 2>/dev/null || echo "")
  if [[ -z "$crontab_out" ]]; then
    _dr_warn "user crontab is empty" "run 'dot update' to install tracked entries"
    return 0
  fi

  # Spot-check: the dot update auto-cron should be present
  if echo "$crontab_out" | grep -q 'dot update --cron'; then
    _dr_ok "auto-update cron entry present"
  else
    _dr_warn "auto-update cron not found" "run 'dot update' to install from merge-hooks.d/cron/cron.d"
  fi
}
