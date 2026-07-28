# shellcheck shell=bash
# _tool_init: source cached tool init output; regenerate if missing or stale.
#
# Usage: _tool_init NAME COMMAND [ARGS...]
#   NAME    — cache key; written below the XDG cache root as shell/NAME.{zsh,bash}
#   COMMAND — command (and optional args) to generate the init script
#
# Cache expires after 7 days, or as soon as the tool itself is newer than the
# cache (so an upgrade's new init — completions, guards, etc. — applies on the
# next shell without waiting out the timer or a manual reloadsh). reloadsh also
# clears the resolved shell cache directory to force immediate regeneration.

# Clear the tool-init cache and re-source guards so integrations reinitialize
# fresh on the next shell start. Called by reloadsh and dotu.
_tool_cache_dir() {
  case "${XDG_CACHE_HOME:-}" in
    /*) REPLY="$XDG_CACHE_HOME/shell" ;;
    *)
      if [[ -n "${HOME:-}" ]]; then
        REPLY="$HOME/.cache/shell"
      else
        REPLY=""
        return 1
      fi
      ;;
  esac
}

_clear_tool_cache() {
  if _tool_cache_dir; then
    find "$REPLY" -maxdepth 1 -type f -delete 2>/dev/null
  fi
  unset __tool_cache_scan_dir __tool_cache_fresh_files
  unset __atuin_sourced __wezterm_sourced
}

# mtime of a file in epoch seconds. Follows symlinks (default stat behavior), so
# a shdeps-style ~/.local/bin/<tool> → checkout swap reports the target's mtime.
_tool_mtime() {
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    zmodload zsh/stat 2>/dev/null
    local -A _st
    zstat -H _st "$1" 2>/dev/null && printf '%s' "${_st[mtime]}"
    return
  fi
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}

_tool_cache_is_fresh() {
  local cache="$1"
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    local _now _cache_mtime
    _now="${EPOCHSECONDS:-$(date +%s)}"
    _cache_mtime=$(_tool_mtime "$cache")
    [[ -n "$_cache_mtime" ]] && ((_now - _cache_mtime < 7 * 86400))
    return
  fi

  local cache_dir="${cache%/*}" _fresh _path _restore_noglob=0
  local -a _candidates
  if [[ "${__tool_cache_scan_dir:-}" != "$cache_dir" ]]; then
    __tool_cache_scan_dir="$cache_dir"
    __tool_cache_fresh_files=()
    _candidates=()
    if [[ "$-" == *f* ]]; then
      _restore_noglob=1
      set +f
    fi
    for _path in "$cache_dir"/*; do
      [[ -f "$_path" ]] && _candidates+=("$_path")
    done
    ((_restore_noglob)) && set -f
    if ((${#_candidates[@]})); then
      while IFS= read -r -d '' _fresh; do
        __tool_cache_fresh_files+=("$_fresh")
      done < <(find -H "${_candidates[@]}" -type f -mtime -7 -print0 2>/dev/null)
    fi
  fi
  for _fresh in "${__tool_cache_fresh_files[@]}"; do
    [[ "$_fresh" == "$cache" ]] && return 0
  done
  return 1
}

_tool_cache_mark_fresh() {
  local cache="$1"
  [[ "${__tool_cache_scan_dir:-}" == "${cache%/*}" ]] || return 0
  __tool_cache_fresh_files+=("$cache")
}

_tool_shdeps_source_emit() {
  local dep="$1"
  local asset_path="$2"
  local asset
  local shdeps_assets="$HOME/.local/lib/dot/core/shdeps-assets.sh"

  [[ -r "$shdeps_assets" ]] || return 1
  # shellcheck disable=SC1090  # stable dotfiles helper path under $HOME
  . "$shdeps_assets"
  asset=$(dot_shdeps_dep_file "$dep" "$asset_path" 2>/dev/null) || return 1
  [[ -r "$asset" ]] || return 1
  cat "$asset"
}

_tool_init() {
  local name="$1"
  shift
  local _cmd="$1"
  local _tool_path
  _tool_path=$(command -v "$_cmd" 2>/dev/null) || return 0
  [[ -n "$_tool_path" ]] || return 0

  local _shell_name
  [[ -n "${ZSH_VERSION:-}" ]] && _shell_name=zsh || _shell_name=bash
  local cache_dir cache
  _tool_cache_dir || return 0
  cache_dir="$REPLY"
  cache="$cache_dir/${name}.${_shell_name}"
  local regen=1

  if [[ -f "$cache" ]] && _tool_cache_is_fresh "$cache"; then
    regen=0
    # Also regenerate if the tool was upgraded after the cache was written, so
    # the new init applies on the very next shell. The shell's file test avoids
    # a separate stat process for every warm integration.
    [[ -f "$_tool_path" && "$_tool_path" -nt "$cache" ]] && regen=1
  fi

  if ((regen)); then
    mkdir -p "${cache%/*}"
    # Generate into a temp and only replace the cache on success with non-empty
    # output. A transient failure (tool momentarily broken, disk full, killed
    # mid-write) must not overwrite a good cache — or leave a fresh-mtime empty
    # one — that the 7-day freshness check would then treat as valid, silently
    # disabling the integration until the timer or a manual reloadsh.
    local _tmp
    _tmp=$(mktemp "${cache}.tmp.XXXXXX" 2>/dev/null) || return
    if "$@" >"$_tmp" 2>/dev/null && [[ -s "$_tmp" ]]; then
      if mv "$_tmp" "$cache"; then
        _tool_cache_mark_fresh "$cache"
      else
        rm -f "$_tmp"
      fi
    else
      rm -f "$_tmp"
    fi
  fi
  # shellcheck disable=SC1090
  [[ -s "$cache" ]] && . "$cache"
}
