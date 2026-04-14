# shellcheck shell=bash
# Merge SSH host definitions from dotfiles into ~/.ssh/config.
# Shared by dotbootstrap and dot (on pull).
#
# Each ssh-config* source file gets its own marked block in ~/.ssh/config,
# delineated by comment markers. Content inside markers is pasted verbatim
# from the source and will be overwritten on each merge. Hand-managed
# entries outside markers are preserved above the managed blocks so they
# win via SSH's first-match-wins semantics.

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

  # Build marked blocks for each source file.
  local -a blocks=()
  for f in "${src_files[@]}"; do
    local name
    name="$(basename "$f")"
    local origin
    origin="$(realpath "$f")"
    local body
    body="$(_ssh_body "$f")"
    [[ -n "$body" ]] || continue
    blocks+=("$(_mb_build "# dot-managed:ssh:$name" "$origin" "$body")")
  done
  [[ ${#blocks[@]} -gt 0 ]] || return 0

  _mb_merge "$dst" "${blocks[@]}"
}
