# shellcheck shell=bash
# Thin adapter for sourceable assets owned by shdeps-managed dependencies.
#
# Dotfiles should not know where dependencies are installed. shdeps owns that
# contract, including local dev-clone precedence, install roots, and dependency
# filters. These helpers only make the `shdeps dep-*` API convenient from
# shell startup files, hooks, and small launchers that need to source a file.

# Directory holding shdeps configuration (dependency lists and install hooks).
_dot_shdeps_conf_dir() {
  printf '%s\n' "$HOME/.config/shdeps"
}

dot_shdeps_dep_file() {
  local conf_dir
  conf_dir="$(_dot_shdeps_conf_dir)"

  if command -v shdeps >/dev/null 2>&1; then
    SHDEPS_CONF_DIR="$conf_dir" command shdeps dep-file "$@"
    return
  fi

  # Fallback for minimal hook environments that have not loaded PATH yet. Treat
  # env-specific hints as candidates rather than hard requirements; test and
  # hook harnesses often carry a temporary SHDEPS_BIN_DIR while the real shdeps
  # CLI still lives at the normal dotfiles install path.
  local shdeps_bin="${SHDEPS_BIN:-}"
  if [ -n "$shdeps_bin" ] && [ -x "$shdeps_bin" ]; then
    SHDEPS_CONF_DIR="$conf_dir" "$shdeps_bin" dep-file "$@"
    return
  fi

  if [ -n "${SHDEPS_BIN_DIR:-}" ] && [ -x "$SHDEPS_BIN_DIR/shdeps" ]; then
    SHDEPS_CONF_DIR="$conf_dir" "$SHDEPS_BIN_DIR/shdeps" dep-file "$@"
    return
  fi

  if [ -x "$HOME/.local/bin/shdeps" ]; then
    SHDEPS_CONF_DIR="$conf_dir" "$HOME/.local/bin/shdeps" dep-file "$@"
    return
  fi

  return 127
}

dot_shdeps_dep_source() {
  local asset
  asset=$(dot_shdeps_dep_file "$@") || return
  [ -n "$asset" ] || return 1
  # shellcheck disable=SC1090 # dependency asset path is resolved by shdeps.
  . "$asset"
}

# Resolve one of AgentGuard's native agent-integration assets.
#
# Keep the repository and provider layout behind this single boundary. Merge
# hooks should know only which runtime they activate and which native file type
# that runtime consumes; AgentGuard owns the event vocabulary, matchers,
# commands, and adapter implementation under the resolved directory. Besides
# keeping dotfiles thin, this makes normal shdeps rules (development-clone
# precedence, install roots, filters, and fleet updates) apply uniformly to
# every supported agent.
#
# Args: $1 = agent directory name, $2 = asset filename
# Prints: resolved dependency path on stdout
dot_agentguard_integration_file() {
  local agent="$1" asset="$2"
  dot_shdeps_dep_file \
    cgraf78/agentguard \
    "share/agentguard/integrations/$agent/$asset"
}

# Print the provider-owned first-line marker for AgentGuard's OpenCode adapter.
# The installer and doctor share this cross-repository identity rather than
# duplicating its literal at each consumer boundary.
dot_agentguard_opencode_marker() {
  printf '%s\n' '// agentguard-managed:opencode-plugin'
}
