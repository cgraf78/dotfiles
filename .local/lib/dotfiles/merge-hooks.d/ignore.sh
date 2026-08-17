# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# shellcheck shell=bash
# Merge ignore patterns from all ignore/ignore.d source files into ~/.ignore.
# Shared by fd and rg for excluding directories from search.

_ignore_sources() {
  # The ignore target needs no native filtering: every family file is an ignore
  # pattern fragment. Family ordering still matters because later managed blocks
  # should appear later in ~/.ignore for humans reading the generated file.
  dot_hook_family_files ignore/ignore.d
}

merge() {
  _dot_tool_present ignore || return 0
  local dst="$HOME/.ignore"

  local -a src_files=()
  local f
  while IFS= read -r f; do
    src_files+=("$f")
  done < <(_ignore_sources)
  [[ ${#src_files[@]} -gt 0 ]] || return 0

  dot_hook_log "  Ignore"

  local -a blocks=()
  for f in "${src_files[@]}"; do
    local name
    name="$(dot_hook_family_marker_name ignore/ignore.d "$f")"
    local origin
    origin="$(realpath "$f")"
    local body
    body=$(<"$f")
    body="${body%$'\n'}"
    [[ -n "$body" ]] || continue
    blocks+=("$(dot_managed_block_build "# dot-managed:ignore:$name" "$origin" "$body")")
  done
  [[ ${#blocks[@]} -gt 0 ]] || return 0

  dot_managed_block_merge_family "$dst" "# dot-managed:ignore:" "${blocks[@]}"
}
