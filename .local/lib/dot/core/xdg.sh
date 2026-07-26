# shellcheck shell=bash
# Shared XDG base-directory policy for dot-managed runtime paths.

# Set REPLY to an absolute XDG base directory. The XDG specification requires
# absolute values, so empty and relative values fall back to the matching HOME
# default instead of becoming dependent on the caller's working directory.
_dot_xdg_home() {
  local kind="$1" value fallback

  case "$kind" in
    config)
      value="${XDG_CONFIG_HOME:-}"
      fallback=".config"
      ;;
    state)
      value="${XDG_STATE_HOME:-}"
      fallback=".local/state"
      ;;
    cache)
      value="${XDG_CACHE_HOME:-}"
      fallback=".cache"
      ;;
    data)
      value="${XDG_DATA_HOME:-}"
      fallback=".local/share"
      ;;
    *) return 2 ;;
  esac

  case "$value" in
    /*)
      REPLY="$value"
      return 0
      ;;
  esac
  case "${HOME:-}" in
    /*)
      REPLY="$HOME/$fallback"
      return 0
      ;;
  esac
  return 1
}

# Set REPLY to a path below one of the supported XDG base directories.
_dot_xdg_path() {
  local kind="$1" suffix="$2" base
  _dot_xdg_home "$kind" || return
  base="$REPLY"
  REPLY="$base/$suffix"
}
