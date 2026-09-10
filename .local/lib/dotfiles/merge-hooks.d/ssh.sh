# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# shellcheck shell=bash
# Merge SSH host definitions from dotfiles into ~/.ssh/config.
# Runs during standalone Dot client convergence.
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
  done < <(dot_hook_family_files_matching \
    ssh/config.d \
    '*.ssh_config' '*.replace/*.ssh_config' \
    '*.ssh-config' '*.replace/*.ssh-config')
}

# Validate rendered ssh_config output with the platform ssh before installing
# it. ssh -G parses the file and prints the effective configuration for a
# dummy host without opening a connection; it exits nonzero when the file
# holds an invalid directive or value. Evaluation matches a real connection
# attempt, so Match exec predicates in the rendered file run here.
_ssh_validate_config() {
  local file="$1" errors
  if ! errors=$(ssh -G dummy -F "$file" 2>&1 >/dev/null); then
    dot_hook_warn "    warning: SSH config validation failed — not installing"
    [[ -n "$errors" ]] && dot_hook_warn "$errors"
    return 1
  fi
}

_ssh_write_if_changed() {
  local dst="$1" text="$2"
  local tmp
  dot_sibling_tmp_for "$dst" || return 1
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
  rest="$(dot_managed_block_strip_family "# dot-managed:ssh:" "$current")"
  rest="$(printf '%s\n' "$rest" | awk '
    length($0) { print; blank = 0; next }
    !blank { print; blank = 1 }
  ')"
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
  _dot_tool_present ssh || return 0
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

  dot_hook_log "  SSH"
  mkdir -p "$HOME/.ssh/controlmasters"
  chmod 700 "$HOME/.ssh/controlmasters"

  # Build marked blocks for each source file.
  local -a blocks=()
  for f in "${src_files[@]}"; do
    local name
    name="$(dot_hook_family_marker_name ssh/config.d "$f")"
    local origin
    origin="$(realpath "$f")"
    local body
    body=$(<"$f")
    body="${body%$'\n'}"
    [[ -n "$body" ]] || continue
    blocks+=("$(dot_managed_block_build "# dot-managed:ssh:$name" "$origin" "$body")")
  done
  [[ ${#blocks[@]} -gt 0 ]] || return 0

  # Render into a staging file beside the destination so the merged output is
  # validated before it can replace a working config. A validation failure
  # keeps the existing file untouched and fails the hook.
  local staging
  dot_sibling_tmp_for "$dst" || return 1
  staging="$REPLY"
  if [[ -f "$dst" ]]; then
    cat "$dst" >"$staging" || {
      dot_hook_warn "    warning: SSH merge failed: cannot stage $dst"
      rm -f "$staging"
      return 1
    }
  fi
  if ! dot_managed_block_merge_family "$staging" "# dot-managed:ssh:" "${blocks[@]}"; then
    dot_hook_warn "    warning: SSH merge failed — keeping existing config"
    rm -f "$staging"
    return 1
  fi
  if ! _ssh_validate_config "$staging"; then
    rm -f "$staging"
    return 1
  fi
  if [[ -f "$dst" ]] && dot_config_files_equal "$staging" "$dst"; then
    rm -f "$staging"
    return 0
  fi
  if ! dot_commit_tmp "$staging" "$dst"; then
    dot_hook_warn "    warning: SSH merge failed: cannot install $dst"
    rm -f "$staging"
    return 1
  fi
}
