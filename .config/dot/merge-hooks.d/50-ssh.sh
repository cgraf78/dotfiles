# shellcheck shell=bash
# Merge SSH host definitions from dotfiles into ~/.ssh/config.
# Shared by dotbootstrap and dot (on pull).
#
# Each ssh-config* source file gets its own marked block in ~/.ssh/config,
# delineated by comment markers. Content inside markers is pasted verbatim
# from the source and will be overwritten on each merge. Hand-managed
# entries outside markers are preserved.

_ssh_marker="# dot-managed:ssh"

# Read a source file, stripping leading comment-only lines (the header
# comment block) and any trailing blank lines. Returns the body via stdout.
_ssh_body() {
  local file="$1"
  local in_header=1 body=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$in_header" -eq 1 ]]; then
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      [[ -z "$line" ]] && continue
      in_header=0
    fi
    body+="$line"$'\n'
  done <"$file"
  # Strip trailing blank lines
  while [[ "$body" == *$'\n\n' ]]; do
    body="${body%$'\n'}"
  done
  printf '%s' "$body"
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

  # Build marked blocks for each source file.
  # Keys are the basename (e.g. "ssh-config", "ssh-config-work").
  local -a src_names=()
  declare -A src_marked=()
  for f in "${src_files[@]}"; do
    local name
    name="$(basename "$f")"
    # Resolve symlinks to show the real origin
    local origin
    if [[ -L "$f" ]]; then
      origin="$(readlink "$f")"
    else
      origin="$name"
    fi
    local body
    body="$(_ssh_body "$f")"
    [[ -n "$body" ]] || continue
    src_names+=("$name")
    src_marked["$name"]="$_ssh_marker:$name begin — $origin"$'\n'"$body"$'\n'"$_ssh_marker:$name end"
  done
  [[ ${#src_names[@]} -gt 0 ]] || return 0

  local current=""
  [[ -f "$dst" ]] && current="$(cat "$dst")"

  # Strip existing marked blocks from the current config.
  local rest="$current"
  for name in "${src_names[@]}"; do
    local block_start="$_ssh_marker:$name begin"
    local block_end="$_ssh_marker:$name end"
    if [[ "$rest" == *"$block_start"* ]]; then
      rest="$(printf '%s\n' "$rest" | sed "/$block_start/,/$block_end/d")"
    fi
  done

  # Collapse runs of 3+ blank lines to 2, then strip leading/trailing
  # whitespace. Prevents blank-line accumulation across repeated merges.
  rest="$(printf '%s\n' "$rest" | cat -s)"
  rest="${rest#"${rest%%[![:space:]]*}"}"
  rest="${rest%"${rest##*[![:space:]]}"}"

  # Build result: hand-managed entries first (SSH is first-match-wins,
  # so local overrides take precedence), then managed blocks.
  local result="$rest"
  for name in "${src_names[@]}"; do
    if [[ -n "$result" ]]; then
      result+=$'\n\n'"${src_marked[$name]}"
    else
      result="${src_marked[$name]}"
    fi
  done
  result+=$'\n'

  # Skip write if nothing changed
  if [[ -f "$dst" ]] && printf '%s' "$result" | cmp -s - "$dst"; then
    return 0
  fi

  printf '%s' "$result" >"$dst.tmp"
  chmod 600 "$dst.tmp"
  mv "$dst.tmp" "$dst"
}
