# shellcheck shell=bash
# Shared helpers for safe sibling temp files.

_dot_sibling_tmp_for() {
  local dst="$1" dir base tmp
  dir="$(dirname "$dst")"
  base="$(basename "$dst")"

  mkdir -p "$dir" || return 1
  tmp=$(mktemp "$dir/${base}.tmp.XXXXXX" 2>/dev/null) || return 1
  REPLY="$tmp"
}
