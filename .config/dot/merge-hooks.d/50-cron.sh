# shellcheck shell=bash
# Install cron entries from ~/.config/dot/cron (tracked) and
# cron.local (machine-local, untracked) into the user crontab.
# Replaces all dot-managed entries (between marker lines) on each run.
# Expands $HOME in cron lines. Sets PATH as a standalone cron variable
# so tools like git, curl, jq are found in cron's minimal environment.
# Idempotent — skips if the installed block already matches.

# Build a clean PATH for cron from the current PATH.
# Keeps: $HOME dirs, /opt/homebrew, /usr/local, and standard system dirs.
# Drops: obscure system dirs (cryptex, munki, etc.) that clutter the crontab.
_cron_path() {
  local result="" dir _dirs
  IFS=: read -ra _dirs <<<"$HOME/.local/bin:$PATH"
  for dir in "${_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    [[ ":$result:" == *":$dir:"* ]] && continue
    case "$dir" in
    "$HOME"/* | /opt/homebrew/* | /usr/local/bin | /usr/bin | /bin | /usr/sbin | /sbin) ;;
    *) continue ;;
    esac
    result="${result:+$result:}$dir"
  done
  echo "$result"
}

# Parse a `# filter:` directive line into _cron_filter_hosts and
# _cron_filter_platforms. Resets both to empty (match-all) first.
# Syntax: # filter: hosts=a,b platforms=linux   or   # filter: *
_cron_parse_filter() {
  local spec="$1"
  _cron_filter_hosts=""
  _cron_filter_platforms=""

  if [[ "$spec" == "*" ]]; then return 0; fi

  local token
  for token in $spec; do
    case "$token" in
    hosts=*)     _cron_filter_hosts="${token#hosts=}" ;;
    platforms=*) _cron_filter_platforms="${token#platforms=}" ;;
    *)           _warn "  warning: unknown filter key: $token" ;;
    esac
  done
}

# Check if current host/platform passes the active cron filter.
# Uses shdeps public match functions when available; includes all if not.
_cron_filter_match() {
  if declare -f shdeps_platform_match &>/dev/null; then
    shdeps_platform_match "$_cron_filter_platforms" || return 1
  fi
  if declare -f shdeps_host_match &>/dev/null; then
    shdeps_host_match "$_cron_filter_hosts" || return 1
  fi
  return 0
}

# Parse a cron file: expand $HOME in entries, skip comments/blanks.
# Supports `# filter:` directives for host/platform filtering.
# Appends processed lines to $_cron_parsed (caller must initialize).
_cron_parse_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  _cron_filter_hosts=""
  _cron_filter_platforms=""

  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*#[[:space:]]*filter:[[:space:]]*(.*) ]]; then
      _cron_parse_filter "${BASH_REMATCH[1]}"
      continue
    fi
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue

    _cron_filter_match || continue

    line="${line//\$HOME/$HOME}"
    if [[ -n "$_cron_parsed" ]]; then
      _cron_parsed="$_cron_parsed"$'\n'"$line"
    else
      _cron_parsed="$line"
    fi
  done <"$file"
}

merge() {
  local cron_file="$HOME/.config/dot/merge-hooks.d/cron"
  local cron_local="$HOME/.config/dot/merge-hooks.d/cron.local"
  local cron_marker="# dot-managed-cron"

  [[ -f "$cron_file" || -f "$cron_local" ]] || return 0

  _log_dim "  cron"

  _cron_parsed=""
  _cron_parse_file "$cron_file"
  _cron_parse_file "$cron_local"

  local current
  current=$(crontab -l 2>/dev/null || true)

  # No active entries — strip any existing managed block and return.
  if [[ -z "$_cron_parsed" ]]; then
    if [[ "$current" == *"$cron_marker begin"* ]]; then
      local stripped
      stripped="$(_mb_strip "$cron_marker" "$current")"
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
  [[ -f "$cron_file" ]] && sources="$cron_file"
  [[ -f "$cron_local" ]] && sources="${sources:+$sources, }$cron_local"
  local body="PATH=$cron_path"$'\n'"$_cron_parsed"
  local managed_block
  managed_block="$(_mb_build "$cron_marker" "$sources" "$body")"

  # Already installed with same content — nothing to do.
  if [[ "$current" == *"$managed_block"* ]]; then
    return 0
  fi

  # Strip any existing managed block.
  local filtered
  filtered="$(_mb_strip "$cron_marker" "$current")"

  # Append the new managed block.
  local new_crontab
  if [[ -n "$filtered" ]]; then
    new_crontab="$filtered"$'\n\n'"$managed_block"
  else
    new_crontab="$managed_block"
  fi

  echo "$new_crontab" | crontab -
}
