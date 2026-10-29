# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# Terminal and WezTerm share the appearance; only macOS has Terminal preferences.
merge() {
  _dot_tool_present terminal || return 0
  local appearance="$HOME/.config/wezterm/appearance.json" defaults_command
  local profile="$HOME/.config/dot/merge-hooks.d/terminal/profile.json"
  [[ -f "$appearance" && -f "$profile" ]] || return 0
  command -v python3 >/dev/null 2>&1 || return 1

  # defaults targets the logged-in account even with a synthetic HOME. Match
  # the existing iTerm2 guard so fixture updates cannot change real preferences.
  _dot_account_scoped_command \
    "Terminal profile" defaults "${DOT_TEST_DEFAULTS:-}" || return 0
  defaults_command="$REPLY"
  dot_hook_log "  Terminal font"
  python3 "${BASH_SOURCE[0]%/*}/lib/terminal-font.py" \
    --defaults "$defaults_command" --appearance "$appearance" --profile "$profile"
}
