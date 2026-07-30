# shellcheck shell=bash
# Lightweight gstack skill registration for dotfiles-managed installs.
#
# Upstream `gstack/setup` also builds browser binaries and installs Playwright
# browsers. Dotfiles only need global skill registration during `dot update`, so
# keep this path limited to links into the existing checkout.

dot_gstack_dir() {
  printf '%s\n' "$HOME/.local/share/garrytan/gstack"
}

dot_gstack_migration_stamp() {
  printf '%s\n' "$HOME/.gstack/.dot-agent-agnostic-install-v1"
}

_dot_gstack_state_dir() {
  printf '%s\n' "$HOME/.gstack"
}

_dot_gstack_generated_skills_dir() {
  printf '%s\n' "$(_dot_gstack_state_dir)/dotfiles-skills"
}

_dot_gstack_claude_skills_dir() {
  printf '%s\n' "$HOME/.claude/skills"
}

# Optional user skip list for upstream gstack skills. Upstream ships every skill
# it has, but agents pay for each registration in their skill-description
# context budget, so a machine may legitimately want only a subset. The path is
# overridable so tests can point at a fixture without writing to the real home.
_dot_gstack_skill_exclude_file() {
  printf '%s\n' "${DOT_GSTACK_SKILL_EXCLUDE_FILE:-$HOME/.config/dot/gstack-skills-exclude}"
}

_dot_gstack_codex_skills_dir() {
  printf '%s\n' "$HOME/.codex/skills"
}

_dot_gstack_gemini_extension_dir() {
  printf '%s\n' "$HOME/.gemini/extensions/gstack"
}

_dot_gstack_gemini_skills_dir() {
  printf '%s\n' "$(_dot_gstack_gemini_extension_dir)/skills"
}

_dot_gstack_warn() {
  if declare -f shdeps_warn >/dev/null 2>&1; then
    shdeps_warn "$@"
  elif declare -f _warn >/dev/null 2>&1; then
    _warn "$@"
  else
    printf '%s\n' "$*" >&2
  fi
}

_dot_gstack_log() {
  if declare -f _log >/dev/null 2>&1; then
    _log "$@"
  elif declare -f shdeps_log >/dev/null 2>&1; then
    shdeps_log "$@"
  fi
}

_DOT_GSTACK_SOURCE_CACHE_DIR=''
_DOT_GSTACK_SOURCE_SKILL_DIRS=()
_DOT_GSTACK_SOURCE_SKILL_NAMES=()
declare -A _DOT_GSTACK_SOURCE_NAME_EXISTS=()
declare -A _DOT_GSTACK_SOURCE_CODEX_NAME_EXISTS=()
declare -A _DOT_GSTACK_SKILL_EXCLUDE=()
_DOT_GSTACK_SKILL_EXCLUDE_LOADED=''
_DOT_GSTACK_GENERATED_SKILL_VERSION='dotfiles-gstack-skill-v5'
_DOT_GSTACK_GEMINI_CONTEXT_VERSION='dotfiles-gstack-gemini-context-v1'
# v12 adds the skill exclude list to the source fingerprint and watch set;
# caches written by v11 cannot prove an exclusion edit was applied.
_DOT_GSTACK_REGISTRATION_CACHE_VERSION='dotfiles-gstack-registration-v12'
_DOT_GSTACK_TARGET_FRESHNESS_CACHE_FILE=''

_dot_gstack_cksum_file() {
  local file="$1"
  if [ -f "$file" ]; then
    cksum <"$file" 2>/dev/null || printf 'unreadable 0\n'
  else
    printf 'missing 0\n'
  fi
}

_dot_gstack_hash_stream() {
  cksum | awk '{ print $1 ":" $2 }'
}

_dot_gstack_registration_cache_file() {
  # Keep the cache in ~/.gstack rather than in any agent-specific skill tree:
  # the decision covers all generated registrations, and ~/.gstack already
  # owns dotfiles/gstack install-shape state across Claude, Codex, and Gemini.
  printf '%s\n' "$(_dot_gstack_state_dir)/.dotfiles-registration-cache-v1"
}

_dot_gstack_has_agent() {
  case "$1" in
    claude) command -v claude >/dev/null 2>&1 ;;
    codex) command -v codex >/dev/null 2>&1 ;;
    gemini) command -v gemini >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

_dot_gstack_agent_state() {
  if _dot_gstack_has_agent "$1"; then
    printf '0\n'
  else
    printf '1\n'
  fi
}
