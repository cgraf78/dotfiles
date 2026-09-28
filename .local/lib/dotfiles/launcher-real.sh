# shellcheck shell=bash
# Shared real-binary resolution for PATH-visible dotfiles launchers.

if ! declare -F dot_xdg_path >/dev/null 2>&1; then
  _dot_launcher_client_dir=$(cd -P -- "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd -P) ||
    return 1
  _dot_launcher_xdg=
  if [[ -n ${DOT_TEST_HOST_HOME:-} ]]; then
    _dot_launcher_xdg=$DOT_TEST_HOST_HOME/.local/lib/dot/xdg.sh
  fi
  if [[ ! -r $_dot_launcher_xdg ]]; then
    _dot_launcher_xdg=${_dot_launcher_client_dir%/dotfiles}/dot/xdg.sh
  fi
  [[ -r $_dot_launcher_xdg ]] || return 1
  # shellcheck source=../dot/xdg.sh disable=SC1091
  . "$_dot_launcher_xdg"
  unset _dot_launcher_client_dir _dot_launcher_xdg
fi

_dot_launcher_physical_dir() {
  cd -- "$1" 2>/dev/null && pwd -P
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

# Report the cached real binary via REPLY when the cache was written under the
# current PATH and still names a valid candidate, or fail. Runs in the caller's
# shell: a command substitution here would cost a fork on every launch.
_dot_launcher_cache_read() {
  local name="$1" self="$2" marker="$3" cache path cached_path
  REPLY=
  _dot_launcher_cache_path "$name" || return 1
  cache="$REPLY"
  REPLY=
  [ -r "$cache" ] || return 1

  {
    IFS= read -r path || path=""
    IFS= read -r cached_path || cached_path=""
  } <"$cache"

  [ "$cached_path" = "${PATH:-}" ] || return 1
  _dot_launcher_candidate_ok "$path" "$self" "$marker" || return 1
  REPLY="$path"
}

# Publish a resolution for later launches and for the prompt, which accepts
# the same file. Rewrite only when the resolved binary changes: sessions whose
# PATH strings differ but resolve the same binary would otherwise replace the
# file on every call, each rewrite costing mkdir/mktemp/mv spawns, while a
# PATH mismatch only costs the reader a fork-free re-resolution.
_dot_launcher_cache_write() {
  local name="$1" path="$2" cache dir tmp cached=""
  _dot_launcher_cache_path "$name" || return 0
  cache="$REPLY"
  if [ -r "$cache" ]; then
    IFS= read -r cached <"$cache" || :
    [ "$cached" = "$path" ] && return 0
  fi
  dir="${cache%/*}"
  [ -d "$dir" ] || mkdir -p -- "$dir" 2>/dev/null || return 0
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

# Resolve the real binary behind a launcher and report it via REPLY, or fail.
# Resolution runs in the caller's shell without command substitutions, since
# every launched command pays for this lookup. The PATH walk stops at the
# first valid candidate instead of listing every match: entries after it, such
# as WSL's Windows mounts, can be slow to stat and cannot change the answer.
_dot_launcher_find_real() {
  local name="$1" self="$2" marker="$3"
  shift 3
  local search dir path fallback

  if _dot_launcher_cache_read "$name" "$self" "$marker"; then
    return 0
  fi

  # The public launcher intentionally shadows the real command on PATH. Resolve
  # by identity and marker, not by name alone, so delegated invocations cannot
  # recurse back into any dotfiles launcher copy. An empty PATH entry names the
  # current directory, as in command lookup.
  search="${PATH:-/usr/local/bin:/usr/bin:/bin}"
  while :; do
    dir="${search%%:*}"
    # Command lookup expands a leading `~` in a PATH entry; keep that so a
    # literal "~/bin" entry resolves as it always has.
    case "$dir" in
      "") dir=. ;;
      \~) [ -z "${HOME:-}" ] || dir="$HOME" ;;
      \~/*) [ -z "${HOME:-}" ] || dir="$HOME/${dir#\~/}" ;;
    esac
    path="$dir/$name"
    if _dot_launcher_candidate_ok "$path" "$self" "$marker"; then
      _dot_launcher_cache_write "$name" "$path"
      REPLY="$path"
      return 0
    fi
    case "$search" in
      *:*) search="${search#*:}" ;;
      *) break ;;
    esac
  done

  for fallback in "$@"; do
    _dot_launcher_candidate_ok "$fallback" "$self" "$marker" || continue
    _dot_launcher_cache_write "$name" "$fallback"
    REPLY="$fallback"
    return 0
  done

  REPLY=
  return 1
}
