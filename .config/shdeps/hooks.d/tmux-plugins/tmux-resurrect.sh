# shellcheck shell=bash
# Protect host-local tmux-resurrect snapshots before the plugin writes them.

post() {
  local base host
  base="$HOME/.local/share/tmux/resurrect"
  host="$base/$(hostname)"

  (umask 077 && mkdir -p "$host")
  chmod 0700 "$base" "$host"
}
