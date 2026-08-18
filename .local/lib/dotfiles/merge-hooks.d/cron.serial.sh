# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# shellcheck shell=bash
# Install cron entries from tracked source layers and cron.local into the user
# crontab. Ordered `cron/cron.d` fragments let base dotfiles and overlays add
# jobs without patching a central file; immediate *.replace groups can express
# mutually-exclusive cron policy when a later overlay must replace an earlier
# choice. `cron.local` remains the last, untracked escape hatch.
# Replaces all dot-managed entries (between marker lines) on each run.
# Expands $HOME in cron lines. Sets PATH as a standalone cron variable
# so tools like git, curl, jq are found in cron's minimal environment.
# Idempotent — skips if the installed block already matches.

# Build a clean PATH for cron from declarative path fragments.
#
# Allowlist-only: read the dirs cron actually needs rather than inherit an
# arbitrary PATH. This is immune to PATH pollution from version managers (mise,
# pyenv, nvm, etc.) that inject per-tool install dirs and can push the generated
# `PATH=...` line past Debian cron's 998-char limit — truncation silently drops
# trailing system dirs (e.g. /usr/bin) and breaks `#!/usr/bin/env bash` lookup
# for cron-invoked scripts.
#
# Dirs that don't exist on the current host are skipped. Ordered `path.d`
# fragments own the order and can use `.replace` groups for environment-specific
# PATH policy.
_cron_path() {
  local result="" source line dir
  while IFS= read -r source; do
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ ^[[:space:]]*$ ]] && continue
      [[ "$line" =~ ^[[:space:]]*# ]] && continue

      dir="$(dot_expand_home "$line")"
      [[ "$dir" != "/" ]] && dir="${dir%/}"
      [[ -n "$dir" ]] || continue

      [[ -d "$dir" ]] || continue
      [[ ":$result:" == *":$dir:"* ]] && continue
      result="${result:+$result:}$dir"
    done <"$source"
  done < <(dot_hook_family_files_matching \
    cron/path.d \
    '*.txt' '*.replace/*.txt' \
    '*.pathlist' '*.replace/*.pathlist')

  if [[ -z "$result" ]]; then
    return 0
  fi

  # Guard against silent truncation by Debian cron (998-char line limit on
  # `PATH=...`). Leave headroom for the `PATH=` prefix and future growth.
  local max=900
  if ((${#result} > max)); then
    dot_hook_warn "  warning: cron PATH is ${#result} chars (>$max) — crond may truncate"
  fi

  echo "$result"
}

# Parse a `# filter:` directive line into the active cron filter state.
# Resets each key to empty (match-all) first.
# Syntax: # filter: hosts=a,b platforms=linux users=chris   or   # filter: *
_cron_parse_filter() {
  local spec="$1"
  _cron_filter_hosts=""
  _cron_filter_platforms=""
  _cron_filter_users=""

  if [[ "$spec" == "*" ]]; then return 0; fi

  local token
  for token in $spec; do
    case "$token" in
      hosts=*) _cron_filter_hosts="${token#hosts=}" ;;
      platforms=*) _cron_filter_platforms="${token#platforms=}" ;;
      users=*) _cron_filter_users="${token#users=}" ;;
      *) dot_hook_warn "  warning: unknown filter key: $token" ;;
    esac
  done
}

# Check whether a comma-separated include/exclude list matches a value.
# Empty specs match everything. Mixed specs apply exclusions first.
_cron_value_match() {
  local spec="${1:-}" current="${2:-}"
  [[ -z "$spec" ]] && return 0

  local item has_include=0 has_exclude=0
  local IFS=','
  for item in $spec; do
    if [[ "$item" == !* ]]; then has_exclude=1; else has_include=1; fi
  done

  if [[ $has_exclude -eq 1 ]]; then
    for item in $spec; do
      [[ "$item" == "!$current" ]] && return 1
    done
  fi

  if [[ $has_include -eq 1 ]]; then
    for item in $spec; do
      [[ "$item" == "$current" ]] && return 0
    done
    return 1
  fi

  return 0
}

_cron_user_match() {
  local spec="${1:-}"
  [[ -z "$spec" ]] && return 0

  local current
  current=$(id -un 2>/dev/null || printf '%s' "${USER:-${LOGNAME:-}}")
  _cron_value_match "$spec" "$current"
}

# Check if current host/platform/user passes the active cron filter. The
# standalone hook API owns host/platform identity; dependency-provider loading
# must not determine whether client cron policy is filtered.
_cron_filter_match() {
  dot_hook_platform_match "$_cron_filter_platforms" || return 1
  dot_hook_host_match "$_cron_filter_hosts" || return 1
  _cron_user_match "$_cron_filter_users" || return 1
  return 0
}

# Parse a cron file: expand $HOME in entries, preserve comments.
# Supports `# filter:` directives for host/platform/user filtering.
# Filter directives are consumed (not passed through to crontab).
# Appends processed lines to $_cron_parsed (caller must initialize).
_cron_parse_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  _cron_filter_hosts=""
  _cron_filter_platforms=""
  _cron_filter_users=""

  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*#[[:space:]]*filter:[[:space:]]*(.*) ]]; then
      _cron_parse_filter "${BASH_REMATCH[1]}"
      continue
    fi

    _cron_filter_match || continue

    line="${line//\$HOME/$HOME}"
    if [[ -n "$_cron_parsed" ]]; then
      _cron_parsed="$_cron_parsed"$'\n'"$line"
    else
      _cron_parsed="$line"
    fi
  done <"$file"
}

# Discover cron source layers in merge order.
#
# The generic family helper owns ordered tracked fragments and `.replace`
# mutual-exclusion. `cron.local` is intentionally outside that family because it
# is untracked machine state: it should always run after tracked policy without
# requiring a private overlay or a committed fragment.
#
# Args: none
#
# Appends source paths to $_cron_sources. The caller must declare/initialize that
# array so this sourced hook can avoid leaking a global when tests invoke helpers
# directly.
_cron_source_files() {
  _cron_sources=()

  local source
  while IFS= read -r source; do
    _cron_sources+=("$source")
  done < <(dot_hook_family_files_matching cron/cron.d '*.cron' '*.replace/*.cron')

  source="$(dot_hook_family cron.local)"
  [[ -f "$source" ]] && _cron_sources+=("$source")
  return 0
}

merge() {
  _dot_tool_present cron || return 0
  local cron_marker="# dot-managed-cron"

  local -a _cron_sources
  _cron_source_files
  ((${#_cron_sources[@]} > 0)) || return 0

  dot_hook_log "  cron"

  _cron_parsed=""
  local source
  for source in "${_cron_sources[@]}"; do
    _cron_parse_file "$source"
  done

  local current
  current=$(crontab -l 2>/dev/null || true)

  # No active entries — strip any existing managed block and return.
  if [[ -z "$_cron_parsed" ]]; then
    if [[ "$current" == *"$cron_marker begin"* ]]; then
      local stripped
      stripped="$(dot_managed_block_strip "$cron_marker" "$current")"
      if [[ -n "$stripped" ]]; then
        echo "$stripped" | crontab -
      else
        crontab -r 2>/dev/null || true
      fi
    fi
    return 0
  fi

  local cron_path
  cron_path=$(_cron_path)
  # List source files that contributed entries.
  local sources=""
  for source in "${_cron_sources[@]}"; do
    sources="${sources:+$sources, }$source"
  done
  local body="$_cron_parsed"
  if [[ -n "$cron_path" ]]; then
    body="PATH=$cron_path"$'\n\n'"$body"
  fi
  local managed_block
  managed_block="$(dot_managed_block_build "$cron_marker" "$sources" "$body")"

  # Already installed with same content — nothing to do.
  if [[ "$current" == *"$managed_block"* ]]; then
    return 0
  fi

  # Strip any existing managed block.
  local filtered
  filtered="$(dot_managed_block_strip "$cron_marker" "$current")"

  # Append the new managed block.
  local new_crontab
  if [[ -n "$filtered" ]]; then
    new_crontab="$filtered"$'\n\n'"$managed_block"
  else
    new_crontab="$managed_block"
  fi

  echo "$new_crontab" | crontab -
}
