# shellcheck shell=bash
# Deploy Sapling hook config fragments to ~/.hgrc.
#
# Only deploys when sl is on PATH. Machines without Sapling get a no-op. Hook
# policy lives under sapling/hgrc.d/ so overlays can replace or extend it
# without editing this reusable merge implementation.

if ! declare -F _merge_hook_family_files_matching >/dev/null 2>&1; then
  # shellcheck source=../merge-hooks.sh
  . "${BASH_SOURCE[0]%/*}/../merge-hooks.sh"
fi

_sapling_hooks_body() {
  local source line

  while IFS= read -r source; do
    while IFS= read -r line || [[ -n "$line" ]]; do
      printf '%s\n' "$(_merge_hook_expand_home "$line")"
    done <"$source"
  done < <(_merge_hook_family_files_matching \
    sapling/hgrc.d \
    '*.ini' '*.replace/*.ini' \
    '*.hgrc' '*.replace/*.hgrc')
}

_sapling_hook_commands_ready() {
  local body="$1" line command executable section=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^[[:space:]]*[#\;] ]] && continue
    if [[ "$line" =~ ^[[:space:]]*\[([^]]+)\] ]]; then
      section="${BASH_REMATCH[1]}"
      continue
    fi
    [[ "$section" == "hooks" ]] || continue
    [[ "$line" == *=* ]] || continue

    command="${line#*=}"
    command="${command#"${command%%[![:space:]]*}"}"
    [[ -n "$command" ]] || continue
    [[ "$command" == python:* ]] && continue

    executable="${command%%[[:space:]]*}"
    if [[ "$executable" == */* ]]; then
      [[ -x "$executable" ]] || return 1
    else
      command -v "$executable" >/dev/null 2>&1 || return 1
    fi
  done <<<"$body"
}

merge() {
  _dot_tool_present sapling || return 0

  local dst="$HOME/.hgrc"

  local body
  body="$(_sapling_hooks_body)"
  [[ -n "$body" ]] || return 0
  _sapling_hook_commands_ready "$body" || return 0

  _log "  Sapling"

  local current old_marker block
  old_marker="# dot-managed:hgrc:repo-check"
  if [ -f "$dst" ]; then
    current="$(cat "$dst")"
    current="$(_mb_strip "$old_marker" "$current")"
    current="$(_mb_strip "# dot-managed:hgrc:sley-legacy" "$current")"
    # Strip legacy managed blocks before writing the current marker. Without
    # this one-time cleanup, users who installed prior variants would get
    # duplicate Sapling entries.
    if ! printf '%s\n' "$current" | cmp -s - "$dst"; then
      printf '%s\n' "$current" >"$dst"
    fi
  fi

  block=$(_mb_build "# dot-managed:hgrc:sley" \
    ".config/dot/merge-hooks.d/sapling/hgrc.d" "$body")

  _mb_merge "$dst" "$block"
}
