#!/bin/bash
# Merge SSH host definitions from dotfiles into ~/.ssh/config.
# Shared by dotbootstrap and dot (on pull).
#
# Policy: dotfiles hosts replace local hosts with the same Host/Match header.
# Local-only hosts are preserved. Order is maintained — new hosts append.

# Parse an SSH config into parallel arrays: headers (ordered) and blocks
# (header → full block text including the header line).
# Each stored block is normalized to end with a single newline (no blank line).
# Args: $1 = file, $2 = headers array name, $3 = blocks assoc-array name
_ssh_parse() {
  local file="$1"
  declare -n _headers="$2" _blocks="$3"
  local header="" block=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^(Host|Match)[[:space:]] ]]; then
      if [[ -n "$header" ]]; then
        # Normalize to end with exactly one newline
        block="${block%$'\n'}"$'\n'
        _headers+=("$header")
        _blocks["$header"]="$block"
      fi
      header="$line"
      block="$line"$'\n'
    elif [[ -n "$header" && -n "$line" ]]; then
      block+="$line"$'\n'
    fi
  done < "$file"

  if [[ -n "$header" ]]; then
    # Normalize to end with exactly one newline
    block="${block%$'\n'}"$'\n'
    _headers+=("$header")
    _blocks["$header"]="$block"
  fi
}

merge() {
  local src="$HOME/.config/dot/merge-hooks.d/ssh-config"
  local dst="$HOME/.ssh/config"

  [[ -f "$src" ]] || return 0

  echo "  SSH"

  # Ensure ~/.ssh exists with correct permissions
  if [[ ! -d "$HOME/.ssh" ]]; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
  fi

  # No existing config — just copy
  if [[ ! -f "$dst" ]]; then
    cp "$src" "$dst"
    chmod 600 "$dst"
    return 0
  fi

  local src_headers=()
  declare -A src_blocks=()
  _ssh_parse "$src" src_headers src_blocks

  local dst_headers=()
  declare -A dst_blocks=()
  _ssh_parse "$dst" dst_headers dst_blocks

  # Source header lookup set
  declare -A src_set=()
  local h
  for h in "${src_headers[@]}"; do
    src_set["$h"]=1
  done

  # Report overwrites
  local conflicts=()
  for h in "${dst_headers[@]}"; do
    [[ -n "${src_set[$h]+x}" ]] && conflicts+=("$h")
  done
  if [[ ${#conflicts[@]} -gt 0 ]]; then
    echo "    overwriting:"
    for h in "${conflicts[@]}"; do
      echo "    $h"
    done
  fi

  # Walk destination blocks, replacing matches with source version.
  # Blocks are separated by blank lines.
  declare -A emitted=()
  local result="" first=1
  for h in "${dst_headers[@]}"; do
    [[ "$first" -eq 1 ]] && first=0 || result+=$'\n'
    if [[ -n "${src_set[$h]+x}" ]]; then
      result+="${src_blocks[$h]}"
    else
      result+="${dst_blocks[$h]}"
    fi
    emitted["$h"]=1
  done

  # Append source-only blocks
  for h in "${src_headers[@]}"; do
    if [[ -z "${emitted[$h]+x}" ]]; then
      result+=$'\n'"${src_blocks[$h]}"
    fi
  done

  # Skip write if nothing changed
  if printf '%s' "$result" | cmp -s - "$dst"; then
    return 0
  fi

  printf '%s' "$result" > "$dst.tmp"
  chmod 600 "$dst.tmp"
  mv "$dst.tmp" "$dst"
}
