# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# shellcheck shell=bash
# Reload the running default tmux server after dot has updated its config.
#
# `tmux source-file` without a socket target deliberately follows tmux's normal
# client contract: it updates the user's default server and does not create one
# just because a scheduled `dot update` ran.

merge() {
  _dot_tool_present tmux || return 0
  local config="$HOME/.config/tmux/tmux.conf" tmux_command

  [[ -r "$config" ]] || return 0
  _dot_account_scoped_command \
    "tmux merge" tmux "${DOT_TEST_TMUX:-}" || return 0
  tmux_command="$REPLY"
  "$tmux_command" has-session >/dev/null 2>&1 || return 0

  dot_hook_log "  tmux"
  "$tmux_command" source-file "$config"
}
