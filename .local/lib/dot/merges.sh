# shellcheck shell=bash
# Run all app config merge scripts from merge-hooks.d/.
# Each file defines merge() — sourced per-script to avoid collisions.

_run_merges() {
  local _scripts=()
  local _script
  while IFS= read -r -d '' _script; do
    _scripts+=("$_script")
  done < <(find "$HOME/.config/dot/merge-hooks.d" -maxdepth 1 -name '*.sh' -print0 2>/dev/null | LC_ALL=C sort -z)

  [[ ${#_scripts[@]} -gt 0 ]] || return 0
  _log_header "==> Merging app config..."

  for _script in "${_scripts[@]}"; do
    unset -f merge 2>/dev/null
    # shellcheck source=/dev/null
    . "$_script"
    if declare -f merge &>/dev/null; then
      if [[ "$DOT_QUIET" -eq 1 ]]; then
        _run_quiet_logged merge "merge failed" "merge"
      else
        merge || true
      fi
      unset -f merge
    fi
  done
}
