# shellcheck shell=bash
# Keep the tracked XDG Git config in the effective global configuration stack.

merge() {
  local managed="$HOME/.config/git/config"
  [[ -f "$managed" ]] || return 0

  local global_config
  if ! global_config=$(git config --global --includes --show-origin --list); then
    _warn "    warning: could not inspect global Git config; skipping managed include"
    return 1
  fi

  # Git installations normally load the XDG file directly. Some hosts with an
  # existing ~/.gitconfig do not, so add an include only when the managed file
  # is absent from the resolved stack.
  case "$global_config" in
    *"file:$managed"$'\t'*) return 0 ;;
  esac

  _log "  Git"
  local include_path
  # shellcheck disable=SC2088 # Git expands this portable path when reading it.
  include_path='~/.config/git/config'
  if ! git config --global --add include.path "$include_path"; then
    _warn "    warning: could not add the managed global Git config include"
    return 1
  fi
}
