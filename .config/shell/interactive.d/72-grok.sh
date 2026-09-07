# shellcheck shell=bash
# Strip a vendor installer block after grok/agent return. Auto-update and
# `agent` share the same binary, so argv sniffing is the wrong trigger.

_grok_rc_lib="$HOME/.local/lib/dotfiles/shell-grok-rc.sh"
# Keep a recovery shell if the helper is absent; grok still runs from PATH.
if [[ ! -r "$_grok_rc_lib" ]]; then
  unset _grok_rc_lib
  return 0
fi
# shellcheck disable=SC1090  # stable path under $HOME, deployed by dotfiles
. "$_grok_rc_lib"
unset _grok_rc_lib

_grok_run() {
  local cmd=$1
  shift
  command "$cmd" "$@"
  local st=$?
  dot_grok_strip_installer_rc
  return "$st"
}

grok() { _grok_run grok "$@"; }
agent() { _grok_run agent "$@"; }
