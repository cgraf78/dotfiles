# shellcheck shell=bash
# Merge SSH host definitions from dotfiles into ~/.ssh/config.
# Shared by dotbootstrap and dot (on pull).
#
# Each ssh/config.d source file gets its own marked block in ~/.ssh/config,
# delineated by comment markers. Content inside markers is pasted verbatim
# from the source and will be overwritten on each merge. Hand-managed
# entries outside markers are preserved above the managed blocks so they
# win via SSH's first-match-wins semantics.

_ssh_config_sources() {
  local f

  # The family helper owns ordering and any .replace mutual-exclusion. SSH still
  # owns native validation: only fragments containing Host/Match blocks become
  # managed ssh_config text, so documentation or disabled files stay inert.
  while IFS= read -r f; do
    grep -qE '^(Host|Match)[[:space:]]' "$f" || continue
    printf '%s\n' "$f"
  done < <(_merge_hook_family_files_matching \
    ssh/config.d \
    '*.ssh_config' '*.replace/*.ssh_config' \
    '*.ssh-config' '*.replace/*.ssh-config')
}

_ssh_write_if_changed() {
  local dst="$1" text="$2"
  local tmp
  _dot_sibling_tmp_for "$dst" || return 1
  tmp="$REPLY"
  printf '%s' "$text" >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  chmod 600 "$tmp" || {
    rm -f "$tmp"
    return 1
  }
  mv "$tmp" "$dst" || {
    rm -f "$tmp"
    return 1
  }
}

_ssh_prune_managed_family() {
  local dst="$1"
  [[ -f "$dst" ]] || return 0

  local current rest
  current=$(cat "$dst")
  rest="$(_mb_strip_family "# dot-managed:ssh:" "$current")"
  rest="$(printf '%s\n' "$rest" | cat -s)"
  rest="${rest#"${rest%%[![:space:]]*}"}"
  rest="${rest%"${rest##*[![:space:]]}"}"

  [[ "$rest" != "$current" ]] || return 0
  if [[ -n "$rest" ]]; then
    _ssh_write_if_changed "$dst" "$rest"$'\n'
  else
    rm -f "$dst"
  fi
}

merge() {
  local dst="$HOME/.ssh/config"

  local -a src_files=()
  local f
  while IFS= read -r f; do
    src_files+=("$f")
  done < <(_ssh_config_sources)
  [[ ${#src_files[@]} -gt 0 ]] || {
    _ssh_prune_managed_family "$dst"
    return 0
  }

  _log "  SSH"
  mkdir -p "$HOME/.ssh/controlmasters"
  chmod 700 "$HOME/.ssh/controlmasters"

  # Build marked blocks for each source file.
  local -a blocks=()
  for f in "${src_files[@]}"; do
    local name
    name="$(_merge_hook_family_marker_name ssh/config.d "$f")"
    local origin
    origin="$(realpath "$f")"
    local body
    body=$(<"$f")
    body="${body%$'\n'}"
    [[ -n "$body" ]] || continue
    blocks+=("$(_mb_build "# dot-managed:ssh:$name" "$origin" "$body")")
  done
  [[ ${#blocks[@]} -gt 0 ]] || return 0

  _mb_merge_family "$dst" "# dot-managed:ssh:" "${blocks[@]}"
}
