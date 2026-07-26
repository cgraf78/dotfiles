# shellcheck shell=bash
# shellcheck disable=SC2154  # _fzf_pick set by 56-dot.sh
# Named directory bookmarks with fuzzy jumping.
# Complements zoxide (frecency) with explicit named bookmarks.

if ! typeset -f _dot_xdg_path >/dev/null 2>&1; then
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    # shellcheck disable=SC2296  # zsh's current sourced-file expansion.
    _dot_marks_source="${(%):-%N}"
  else
    _dot_marks_source="${BASH_SOURCE[0]}"
  fi
  # shellcheck source=../../../.local/lib/dot/core/xdg.sh disable=SC1091
  . "${_dot_marks_source%/*}/../../../.local/lib/dot/core/xdg.sh"
  unset _dot_marks_source
fi
_dot_xdg_path data marks || return
_MARKS_DIR="$REPLY"

_valid_mark_name() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

# Save current directory as a named bookmark.
# Usage: mark [name]   (default: directory basename)
mark() {
  local name="${1:-$(basename "$PWD")}"
  if ! _valid_mark_name "$name"; then
    echo "error: bookmark name must match [A-Za-z0-9._-]: $name" >&2
    return 1
  fi
  mkdir -p "$_MARKS_DIR"
  printf '%s\n' "$PWD" >"$_MARKS_DIR/$name"
  echo "marked: $name -> $PWD"
}

# Jump to a named bookmark.
# Usage: j [name]   -- exact match, fuzzy fallback, or fzf picker
j() {
  if [[ ! -d "$_MARKS_DIR" ]] || [[ -z "$(command ls -A "$_MARKS_DIR" 2>/dev/null)" ]]; then
    echo "no bookmarks set (use 'mark' to create one)" >&2
    return 1
  fi

  local name target

  if [[ $# -eq 0 ]]; then
    name=$(
      command ls -1 "$_MARKS_DIR" |
        fzf "${_fzf_pick[@]}" --prompt="mark> " \
          --preview="cat '$_MARKS_DIR/{}'"
    ) || return
  elif [[ -f "$_MARKS_DIR/$1" ]]; then
    name="$1"
  else
    name=$(
      command ls -1 "$_MARKS_DIR" |
        fzf "${_fzf_pick[@]}" --prompt="mark> " --query="$1" --select-1 \
          --preview="cat '$_MARKS_DIR/{}'"
    ) || return
  fi

  [[ -n "$name" ]] || return
  target=$(cat "$_MARKS_DIR/$name")

  if [[ ! -d "$target" ]]; then
    echo "error: target no longer exists: $target" >&2
    echo "run 'unmark $name' to remove stale bookmark" >&2
    return 1
  fi

  cd "$target" || return
}

# List all bookmarks.
marks() {
  if [[ ! -d "$_MARKS_DIR" ]] || [[ -z "$(command ls -A "$_MARKS_DIR" 2>/dev/null)" ]]; then
    echo "no bookmarks set"
    return
  fi

  local name target
  for f in "$_MARKS_DIR"/*; do
    name=$(basename "$f")
    target=$(cat "$f")
    if [[ -d "$target" ]]; then
      printf '  %-20s -> %s\n' "$name" "$target"
    else
      printf '  %-20s -> %s (missing)\n' "$name" "$target"
    fi
  done
}

# Remove a bookmark.
# Usage: unmark <name>
unmark() {
  if [[ -z "${1:-}" ]]; then
    echo "usage: unmark <name>" >&2
    return 1
  fi
  if ! _valid_mark_name "$1"; then
    echo "error: bookmark name must match [A-Za-z0-9._-]: $1" >&2
    return 1
  fi
  if [[ -f "$_MARKS_DIR/$1" ]]; then
    rm "$_MARKS_DIR/$1"
    echo "unmarked: $1"
  else
    echo "error: no bookmark named '$1'" >&2
    return 1
  fi
}
