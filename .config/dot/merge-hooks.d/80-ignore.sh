# shellcheck shell=bash
# Merge ignore patterns from all ignore-* source files into ~/.ignore.
# Shared by fd and rg for excluding directories from search.

merge() {
  local hooks_dir="$HOME/.config/dot/merge-hooks.d"
  local dst="$HOME/.ignore"

  local -a src_files=()
  local f
  for f in "$hooks_dir"/ignore-*; do
    [[ -f "$f" ]] || continue
    src_files+=("$f")
  done
  [[ ${#src_files[@]} -gt 0 ]] || return 0

  _log "  Ignore"

  local -a blocks=()
  for f in "${src_files[@]}"; do
    local name
    name="$(basename "$f")"
    local origin
    origin="$(realpath "$f")"
    local body
    body=$(<"$f")
    body="${body%$'\n'}"
    [[ -n "$body" ]] || continue
    blocks+=("$(_mb_build "# dot-managed:ignore:$name" "$origin" "$body")")
  done
  [[ ${#blocks[@]} -gt 0 ]] || return 0

  _mb_merge "$dst" "${blocks[@]}"
}
