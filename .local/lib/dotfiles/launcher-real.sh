# shellcheck shell=bash
# Shared real-binary resolution for PATH-visible dotfiles launchers.

if ! declare -F dot_xdg_path >/dev/null 2>&1; then
  _dot_launcher_library_home=${DOT_TEST_HOST_HOME:-${HOME:-}}
  _dot_launcher_xdg=$_dot_launcher_library_home/.local/lib/dot/xdg.sh
  # shellcheck source=../dot/xdg.sh disable=SC1091
  . "$_dot_launcher_xdg"
  unset _dot_launcher_library_home _dot_launcher_xdg
fi

_dot_launcher_physical_dir() {
  cd -- "$1" 2>/dev/null && pwd -P
}

_dot_launcher_file_id() {
  local path="$1" dir base
  case "$path" in
    */*)
      dir="${path%/*}"
      base="${path##*/}"
      ;;
    *)
      dir="."
      base="$path"
      ;;
  esac
  dir=$(_dot_launcher_physical_dir "$dir") || return 1
  printf '%s/%s\n' "$dir" "$base"
}

_dot_launcher_same_file() {
  local left="$1" right="$2"
  [ -e "$left" ] && [ -e "$right" ] && [ "$left" -ef "$right" ]
}

_dot_launcher_has_marker() {
  local path="$1" marker="$2" line=""
  [ -f "$path" ] || return 1

  {
    IFS= read -r line || return 1
    IFS= read -r line || return 1
  } <"$path"

  [ "$line" = "$marker" ]
}

_dot_launcher_candidate_ok() {
  local path="$1" self="$2" marker="$3"
  [ -n "$path" ] || return 1
  [ -x "$path" ] || return 1
  [ ! -d "$path" ] || return 1
  _dot_launcher_same_file "$path" "$self" && return 1
  # Root and sudo shells can inherit another user's ~/.local/bin. Identity
  # checks only skip the current copy; skip every dotfiles launcher copy so two
  # accounts cannot bounce between wrappers while looking for the real binary.
  _dot_launcher_has_marker "$path" "$marker" && return 1
  return 0
}

_dot_launcher_cache_path() {
  local name="$1"
  dot_xdg_path cache "dotfiles/${name}-real"
}

_dot_launcher_cache_read() {
  local name="$1" self="$2" marker="$3" cache path cached_path
  _dot_launcher_cache_path "$name" || return 1
  cache="$REPLY"
  [ -r "$cache" ] || return 1

  {
    IFS= read -r path || path=""
    IFS= read -r cached_path || cached_path=""
  } <"$cache"

  [ "$cached_path" = "${PATH:-}" ] || return 1
  _dot_launcher_candidate_ok "$path" "$self" "$marker" || return 1
  printf '%s\n' "$path"
}

_dot_launcher_cache_write() {
  local name="$1" path="$2" cache dir tmp
  _dot_launcher_cache_path "$name" || return 0
  cache="$REPLY"
  dir="${cache%/*}"
  mkdir -p -- "$dir" 2>/dev/null || return 0
  tmp=$(mktemp "${cache}.XXXXXX" 2>/dev/null) || return 0
  {
    printf '%s\n' "$path"
    printf '%s\n' "${PATH:-}"
  } >"$tmp" 2>/dev/null || {
    rm -f -- "$tmp"
    return 0
  }
  mv -f -- "$tmp" "$cache" 2>/dev/null || rm -f -- "$tmp"
}

_dot_launcher_find_real() {
  local name="$1" self="$2" marker="$3"
  shift 3
  local path fallback

  if path=$(_dot_launcher_cache_read "$name" "$self" "$marker"); then
    printf '%s\n' "$path"
    return 0
  fi

  # The public launcher intentionally shadows the real command on PATH. Resolve
  # by identity and marker, not by name alone, so delegated invocations cannot
  # recurse back into any dotfiles launcher copy.
  while IFS= read -r path; do
    _dot_launcher_candidate_ok "$path" "$self" "$marker" || continue
    _dot_launcher_cache_write "$name" "$path"
    printf '%s\n' "$path"
    return 0
  done < <(PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}" type -P -a "$name" 2>/dev/null)

  for fallback in "$@"; do
    _dot_launcher_candidate_ok "$fallback" "$self" "$marker" || continue
    _dot_launcher_cache_write "$name" "$fallback"
    printf '%s\n' "$fallback"
    return 0
  done

  return 1
}
