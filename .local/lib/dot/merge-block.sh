# shellcheck shell=bash
# Shared helpers for managing marked blocks in config files.
#
# A marked block looks like:
#   # <marker> begin
#   # DO NOT EDIT: manual changes will be overwritten by dot update
#   # source: /path/to/source
#   <content>
#   # <marker> end
#
# Functions:
#   _mb_build    — assemble a marked block string
#   _mb_strip    — remove a marked block from a string
#   _mb_merge    — merge marked blocks into a file (hand-managed first)

# Build a marked block string.
# Args: $1 = marker, $2 = source path, $3 = body content
# Returns the block via stdout.
_mb_build() {
  local marker="$1" source="$2" body="$3"
  printf '%s\n%s\n%s\n%s\n%s' \
    "$marker begin" \
    "# DO NOT EDIT: manual changes will be overwritten by dot update" \
    "# source: $source" \
    "$body" \
    "$marker end"
}

# Strip a marked block from a string.
# Args: $1 = marker (matched as prefix of begin/end lines), $2 = input string
# Returns the result via stdout.
_mb_strip() {
  local marker="$1" input="$2"
  if [[ "$input" == *"$marker begin"* ]]; then
    printf '%s\n' "$input" | sed "/$marker begin/,/$marker end/d"
  else
    printf '%s\n' "$input"
  fi
}

# Merge marked blocks into a file. Hand-managed content stays first
# (important for SSH first-match-wins), managed blocks append at the end.
#
# Args: $1 = destination file path
#       $2..N = marked block strings (each from _mb_build)
#
# Creates the file if it doesn't exist. Skips write if nothing changed.
# Sets permissions to 600 on the destination file.
_mb_merge() {
  local dst="$1"
  shift
  local -a blocks=("$@")

  # Ensure parent directory exists
  local dst_dir
  dst_dir="$(dirname "$dst")"
  if [[ ! -d "$dst_dir" ]]; then
    mkdir -p "$dst_dir"
    chmod 700 "$dst_dir"
  fi

  local current=""
  [[ -f "$dst" ]] && current="$(cat "$dst")"

  # Strip existing managed blocks from the current config.
  local rest="$current"
  local block marker
  for block in "${blocks[@]}"; do
    # Extract marker from the first line ("# marker begin" → "# marker")
    marker="${block%% begin*}"
    rest="$(_mb_strip "$marker" "$rest")"
  done

  # Collapse runs of 3+ blank lines to 2, then strip leading/trailing
  # whitespace. Prevents blank-line accumulation across repeated merges.
  rest="$(printf '%s\n' "$rest" | cat -s)"
  rest="${rest#"${rest%%[![:space:]]*}"}"
  rest="${rest%"${rest##*[![:space:]]}"}"

  # Build result: hand-managed entries first, then managed blocks.
  local result="$rest"
  for block in "${blocks[@]}"; do
    if [[ -n "$result" ]]; then
      result+=$'\n\n'"$block"
    else
      result="$block"
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
