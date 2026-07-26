# shellcheck shell=bash
# Public API for dotfiles-managed gstack skill registration.
#
# This file is sourced by both the shdeps gstack hook and the dot merge hook.
# Keep public entrypoints here and put implementation details in neighboring
# modules so the registration flow remains readable.

_dot_gstack_register_module_dir() {
  local src="${BASH_SOURCE[0]}"
  (cd "$(dirname "$src")" >/dev/null 2>&1 && pwd -P)
}

_DOT_GSTACK_REGISTER_DIR="${_DOT_GSTACK_REGISTER_DIR:-$(_dot_gstack_register_module_dir)}"

# shellcheck source=../core/temp.sh
. "$_DOT_GSTACK_REGISTER_DIR/../core/temp.sh"
# shellcheck source=paths.sh
. "$_DOT_GSTACK_REGISTER_DIR/paths.sh"
# shellcheck source=source.sh
. "$_DOT_GSTACK_REGISTER_DIR/source.sh"
# shellcheck source=managed.sh
. "$_DOT_GSTACK_REGISTER_DIR/managed.sh"
# shellcheck source=migration.sh
. "$_DOT_GSTACK_REGISTER_DIR/migration.sh"
# shellcheck source=generated.sh
. "$_DOT_GSTACK_REGISTER_DIR/generated.sh"
# shellcheck source=targets.sh
. "$_DOT_GSTACK_REGISTER_DIR/targets.sh"
# shellcheck source=cache.sh
. "$_DOT_GSTACK_REGISTER_DIR/cache.sh"

dot_gstack_register_all() {
  local gstack_dir stamp
  gstack_dir=$(dot_gstack_dir)
  stamp=$(dot_gstack_migration_stamp)

  [ -d "$gstack_dir" ] || return 0
  [ -f "$gstack_dir/SKILL.md" ] || {
    _dot_gstack_warn "    warning: gstack checkout missing SKILL.md at $gstack_dir"
    return 1
  }

  if _dot_gstack_registration_cache_current "$gstack_dir"; then
    _dot_gstack_log "  gstack skill registration current"
    touch "$stamp"
    return 0
  fi

  _dot_gstack_log "  gstack skill registration"
  _dot_gstack_reset_source_cache
  _dot_gstack_migrate_state_dir "$gstack_dir"
  _dot_gstack_load_source_skills "$gstack_dir"
  _dot_gstack_write_generated_skills "$gstack_dir"

  # Generated skills rewrite legacy Claude runtime paths to the checkout, so no
  # agent needs a global ~/.claude/skills/gstack compatibility root.
  _dot_gstack_register_claude "$gstack_dir"
  if _dot_gstack_has_agent codex; then
    _dot_gstack_register_codex "$gstack_dir"
  else
    _dot_gstack_unregister_codex "$gstack_dir"
  fi
  if _dot_gstack_has_agent gemini; then
    _dot_gstack_register_gemini "$gstack_dir"
  else
    _dot_gstack_unregister_gemini
  fi

  _dot_gstack_write_registration_cache "$gstack_dir" || true
  touch "$stamp"
}

dot_gstack_unregister_all() {
  local gstack_dir claude_dir i name link_name
  gstack_dir=$(dot_gstack_dir)
  claude_dir="$(_dot_gstack_claude_skills_dir)"

  _dot_gstack_reset_source_cache
  if [ -d "$gstack_dir" ]; then
    _dot_gstack_load_source_skills "$gstack_dir"
    for i in "${!_DOT_GSTACK_SOURCE_SKILL_NAMES[@]}"; do
      name="${_DOT_GSTACK_SOURCE_SKILL_NAMES[$i]}"
      link_name=$(_dot_gstack_codex_skill_name "$name")
      _dot_gstack_remove_skill_link "$claude_dir/$link_name"
      _dot_gstack_remove_skill_link "$claude_dir/$name"
    done
  fi

  _dot_gstack_remove_link_if_managed "$claude_dir/gstack"
  _dot_gstack_remove_link_if_managed "$claude_dir/connect-chrome"
  _dot_gstack_unregister_codex "$gstack_dir"
  _dot_gstack_unregister_gemini
  _dot_gstack_unregister_generated_skills
  rm -f "$(dot_gstack_migration_stamp)"
}
