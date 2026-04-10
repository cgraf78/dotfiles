#!/bin/bash
# Cron entry management: install/update dot-managed cron entries
# from tracked and machine-local cron files.

DOT_CRON_FILE="$HOME/.config/dot/cron"
DOT_CRON_LOCAL="$HOME/.config/dot/cron.local"
DOT_CRON_MARKER="# dot-managed-cron"

# Build a clean PATH for cron from the current PATH.
# Keeps: $HOME dirs, /opt/homebrew, /usr/local, and standard system dirs.
# Drops: obscure system dirs (cryptex, munki, etc.) that clutter the crontab.
_cron_path() {
  local result="" dir _dirs
  IFS=: read -ra _dirs <<< "$HOME/.local/bin:$PATH"
  for dir in "${_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    [[ ":$result:" == *":$dir:"* ]] && continue
    # Keep user dirs, homebrew, /usr/local, and standard system dirs.
    case "$dir" in
      "$HOME"/*|/opt/homebrew/*|/usr/local/bin|/usr/bin|/bin|/usr/sbin|/sbin) ;;
      *) continue ;;
    esac
    result="${result:+$result:}$dir"
  done
  echo "$result"
}

# Parse a cron file: expand $HOME in entries, skip comments/blanks.
# Appends processed lines to $DOT_CRON_PARSED (caller must initialize).
_parse_cron_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue
    line="${line//\$HOME/$HOME}"
    if [[ -n "$DOT_CRON_PARSED" ]]; then
      DOT_CRON_PARSED="$DOT_CRON_PARSED"$'\n'"$line"
    else
      DOT_CRON_PARSED="$line"
    fi
  done < "$file"
}

# Install cron entries from ~/.config/dot/cron (tracked) and
# ~/.config/dot/cron.local (machine-local, untracked) into the user crontab.
# Replaces all dot-managed entries (between marker lines) on each run.
# Expands $HOME in cron lines. Sets PATH as a standalone cron variable
# so tools like git, curl, jq are found in cron's minimal environment.
# Idempotent — skips if the installed block already matches.
_install_cron() {
  [[ -f "$DOT_CRON_FILE" || -f "$DOT_CRON_LOCAL" ]] || return 0

  DOT_CRON_PARSED=""
  _parse_cron_file "$DOT_CRON_FILE"
  _parse_cron_file "$DOT_CRON_LOCAL"

  local block_start="$DOT_CRON_MARKER begin"
  local block_end="$DOT_CRON_MARKER end"
  local current
  current=$(crontab -l 2>/dev/null || true)

  # No active entries — strip any existing managed block and return.
  if [[ -z "$DOT_CRON_PARSED" ]]; then
    if [[ "$current" == *"$block_start"* ]]; then
      local stripped
      stripped=$(echo "$current" | sed "/$block_start/,/$block_end/d")
      if [[ -n "$stripped" ]]; then
        echo "$stripped" | crontab -
      else
        crontab -r 2>/dev/null || true
      fi
      _log_ok "  cron entries removed"
    fi
    return 0
  fi

  local cron_path
  cron_path=$(_cron_path)
  local managed_block="$block_start"$'\n'"PATH=$cron_path"$'\n'"$DOT_CRON_PARSED"$'\n'"$block_end"

  # Already installed with same content — nothing to do.
  if [[ "$current" == *"$managed_block"* ]]; then
    _log_dim "  cron up to date"
    return 0
  fi

  # Strip any existing managed block.
  local filtered
  if [[ "$current" == *"$block_start"* ]]; then
    filtered=$(echo "$current" | sed "/$block_start/,/$block_end/d")
  else
    filtered="$current"
  fi

  # Append the new managed block.
  local new_crontab
  if [[ -n "$filtered" ]]; then
    new_crontab="$filtered"$'\n\n'"$managed_block"
  else
    new_crontab="$managed_block"
  fi

  echo "$new_crontab" | crontab -
  _log_ok "  cron installed"
}
