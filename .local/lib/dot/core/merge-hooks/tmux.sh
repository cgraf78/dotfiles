# shellcheck shell=bash
# Reload the running default tmux server after dot has updated its config.
#
# `tmux source-file` without a socket target deliberately follows tmux's normal
# client contract: it updates the user's default server and does not create one
# just because a scheduled `dot update` ran.

merge() {
  local config="$HOME/.config/tmux/tmux.conf"

  [[ -r "$config" ]] || return 0
  command -v tmux >/dev/null 2>&1 || return 0
  tmux has-session >/dev/null 2>&1 || return 0

  _log "  tmux"
  tmux source-file "$config"
}
