# shellcheck shell=bash
# Install the source-managed OpenCode AgentGuard plugin.

_dot_opencode_hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || return
_dot_opencode_source_dir="${DOT_OPENCODE_SOURCE_DIR:-$_dot_opencode_hook_dir/../../../../../.config/dot/merge-hooks.d/opencode}"
_dot_opencode_marker='// dot-managed:opencode-agentguard-plugin'

_dot_opencode_managed_target() {
  local target="$1" first_line=""

  [[ -f "$target" && ! -L "$target" ]] || return 1
  IFS= read -r first_line <"$target" || true
  [[ "$first_line" == "$_dot_opencode_marker" ]]
}

merge() {
  local src="$_dot_opencode_source_dir/agentguard.js"
  local dst="$HOME/.config/opencode/plugins/dotfiles-agentguard.js"
  local tmp=""

  if [[ ! -f "$src" ]]; then
    if _dot_opencode_managed_target "$dst"; then
      _log "  OpenCode"
      rm -f "$dst"
    fi
    return 0
  fi

  if ! _dot_opencode_managed_target "$src"; then
    _warn "    warning: invalid OpenCode AgentGuard plugin source — preserving target"
    return 1
  fi

  if [[ -e "$dst" || -L "$dst" ]] && ! _dot_opencode_managed_target "$dst"; then
    _warn "    warning: unmanaged $dst — preserving"
    return 0
  fi

  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
    return 0
  fi

  mkdir -p "${dst%/*}"
  _log "  OpenCode"
  _merge_hook_tmp_for "$dst" || return 1
  tmp="$REPLY"
  if ! cp "$src" "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  if ! _merge_hook_commit_tmp "$tmp" "$dst"; then
    rm -f "$tmp"
    return 1
  fi
}
