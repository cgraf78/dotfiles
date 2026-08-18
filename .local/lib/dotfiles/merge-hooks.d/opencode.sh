# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# shellcheck shell=bash
# Install AgentGuard's provider-owned OpenCode plugin.

_dot_opencode_provider_source() {
  local source="$1" first_line=""

  [[ -f "$source" && ! -L "$source" ]] || return 1
  IFS= read -r first_line <"$source" || true
  # Unlike an installed target, a freshly resolved provider asset has no
  # migration reason to use dotfiles' retired marker. Requiring AgentGuard's
  # marker here prevents an old or misresolved consumer file from being
  # promoted as the new canonical adapter.
  [[ "$first_line" == "$(dot_agentguard_opencode_marker)" ]]
}

_dot_opencode_managed_target() {
  local target="$1" first_line=""

  [[ -f "$target" && ! -L "$target" ]] || return 1
  IFS= read -r first_line <"$target" || true
  # Accept the old dotfiles marker only as a migration input. The next
  # successful install replaces it with AgentGuard's marker, after which the
  # provider can evolve the adapter without dotfiles owning its identity.
  [[ "$first_line" == "$(dot_agentguard_opencode_marker)" ||
  "$first_line" == "$(dot_agentguard_opencode_legacy_marker)" ]]
}

merge() {
  _dot_tool_present opencode || return 0
  local src=""
  # Retain the historical target filename so an update replaces the existing
  # managed plugin in place instead of briefly loading two copies. The filename
  # is an installation detail; all executable bytes come from AgentGuard.
  local dst="$HOME/.config/opencode/plugins/dotfiles-agentguard.js"
  local tmp=""

  # Dependency resolution can be unavailable during bootstrap, an interrupted
  # update, or the coordinated rollout of the provider repository. Preserve a
  # previously installed plugin in every such case; absence is not evidence
  # that the user intentionally disabled AgentGuard.
  src=$(dot_agentguard_integration_file opencode agentguard.js 2>/dev/null) || src=""
  if [[ ! -f "$src" ]]; then
    dot_hook_warn "    warning: AgentGuard opencode integration unavailable — preserving $dst"
    return 1
  fi

  if ! _dot_opencode_provider_source "$src"; then
    dot_hook_warn "    warning: invalid OpenCode AgentGuard plugin source — preserving target"
    return 1
  fi

  if [[ -e "$dst" || -L "$dst" ]] && ! _dot_opencode_managed_target "$dst"; then
    dot_hook_warn "    warning: unmanaged $dst — preserving"
    return 0
  fi

  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
    return 0
  fi

  mkdir -p "${dst%/*}"
  dot_hook_log "  OpenCode"
  dot_sibling_tmp_for "$dst" || return 1
  tmp="$REPLY"
  if ! cp "$src" "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  if ! dot_commit_tmp "$tmp" "$dst"; then
    rm -f "$tmp"
    return 1
  fi
}
