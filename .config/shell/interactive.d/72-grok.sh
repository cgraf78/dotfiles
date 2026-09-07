# shellcheck shell=bash
# Wrap grok so vendor update/doctor paths cannot leave their installer
# block in the tracked thin loaders. Completions and PATH are already
# owned by 90-path.sh and 70-integrations.*.

_grok_rc_lib="$HOME/.local/lib/dotfiles/shell-grok-rc.sh"
# Keep a recovery shell if the helper is absent; grok still runs from PATH.
if [[ ! -r "$_grok_rc_lib" ]]; then
  unset _grok_rc_lib
  return 0
fi
# shellcheck disable=SC1090  # stable path under $HOME, deployed by dotfiles
. "$_grok_rc_lib"
unset _grok_rc_lib

grok() {
  command grok "$@"
  local st=$?
  local arg
  for arg in "$@"; do
    case "$arg" in
      update | doctor)
        dot_grok_strip_installer_rc
        break
        ;;
    esac
  done
  return "$st"
}
