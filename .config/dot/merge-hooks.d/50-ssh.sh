# shellcheck shell=bash
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
  done <"$file"

  if [[ -n "$header" ]]; then
    # Normalize to end with exactly one newline
    block="${block%$'\n'}"$'\n'
    _headers+=("$header")
    _blocks["$header"]="$block"
  fi
}

merge() {
  local hooks_dir="$HOME/.config/dot/merge-hooks.d"
  local dst="$HOME/.ssh/config"

  # Collect all ssh-config* files (personal, work, etc.)
  local -a src_files=()
  local f
  for f in "$hooks_dir"/ssh-config*; do
    [[ -f "$f" ]] || continue
    grep -qE '^(Host|Match)[[:space:]]' "$f" && src_files+=("$f")
  done
  [[ ${#src_files[@]} -gt 0 ]] || return 0

  _log_dim "  SSH"

  # Ensure ~/.ssh exists with correct permissions
  if [[ ! -d "$HOME/.ssh" ]]; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
  fi

  # Parse all source files into a single set of blocks.
  # Later files override earlier ones for the same Host/Match header.
  local src_headers=()
  declare -A src_blocks=()
  for f in "${src_files[@]}"; do
    local file_headers=()
    declare -A file_blocks=()
    _ssh_parse "$f" file_headers file_blocks
    local h
    for h in "${file_headers[@]}"; do
      if [[ -z "${src_blocks[$h]+x}" ]]; then
        src_headers+=("$h")
      fi
      src_blocks["$h"]="${file_blocks[$h]}"
    done
    unset file_headers file_blocks
  done

  # No existing config — write combined source
  if [[ ! -f "$dst" ]]; then
    local result="" first=1
    for h in "${src_headers[@]}"; do
      [[ "$first" -eq 1 ]] && first=0 || result+=$'\n'
      result+="${src_blocks[$h]}"
    done
    printf '%s' "$result" >"$dst"
    chmod 600 "$dst"
    return 0
  fi

  local dst_headers=()
  declare -A dst_blocks=()
  _ssh_parse "$dst" dst_headers dst_blocks

  # Source header lookup set
  declare -A src_set=()
  local h
  for h in "${src_headers[@]}"; do
    src_set["$h"]=1
  done

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

  printf '%s' "$result" >"$dst.tmp"
  chmod 600 "$dst.tmp"
  mv "$dst.tmp" "$dst"
}
