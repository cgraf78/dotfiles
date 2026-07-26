# shellcheck shell=bash
# Agent-specific registration targets.
#
# Claude, Codex, and Gemini have different skill roots, but they all consume
# the same generated skill tree. Keep per-agent filesystem policy here so the
# public API can stay focused on the high-level register/unregister flow.

_dot_gstack_legacy_codex_fixed_copy_is_gstack() {
  local skill_md="$1"

  grep -Eq \
    '^<!-- dotfiles-managed-source: .*/garrytan/gstack/.*/SKILL.md -->$|/garrytan/gstack/' \
    "$skill_md" 2>/dev/null && return 0

  # Old sync-skills-to-codex fixed copies lacked a dotfiles marker, so their
  # safest stable fingerprint is the generated gstack body: the template marker
  # plus gstack runtime paths. A prose "(gstack)" mention alone is too broad for
  # a destructive cleanup of generic names like "qa" or "review".
  grep -q 'AUTO-GENERATED from SKILL.md.tmpl' "$skill_md" 2>/dev/null &&
    grep -q '[~]/[.]claude/skills/gstack' "$skill_md" 2>/dev/null
}

_dot_gstack_prune_legacy_unprefixed_codex() {
  local skills_dir="$1" dst base

  for dst in "$skills_dir"/*; do
    [ -e "$dst" ] || [ -L "$dst" ] || continue
    base=$(basename "$dst")
    [ "$base" = "gstack" ] && continue
    _dot_gstack_is_prefixed_skill_name "$base" && continue

    if _dot_gstack_skill_dir_is_managed "$dst"; then
      rm -rf "$dst"
      continue
    fi

    [ -f "$dst/SKILL.md" ] || continue
    [ "$(_dot_gstack_skill_name "$dst")" = "$base" ] || continue
    _dot_gstack_legacy_codex_fixed_copy_is_gstack "$dst/SKILL.md" || continue
    rm -rf "$dst"
  done
}

_dot_gstack_prune_stale_claude() {
  local gstack_dir="$1" skills_dir="$2" dst base

  [ -d "$skills_dir" ] || return 0
  _dot_gstack_load_source_skills "$gstack_dir"
  for dst in "$skills_dir"/*; do
    [ -e "$dst" ] || [ -L "$dst" ] || continue
    base=$(basename "$dst")
    _dot_gstack_skill_dir_is_managed "$dst" || continue
    _dot_gstack_codex_skill_name_exists "$gstack_dir" "$base" && continue
    _dot_gstack_remove_skill_link "$dst"
  done
}

_dot_gstack_prune_stale_codex() {
  local gstack_dir="$1" skills_dir="$2" dst base

  [ -d "$skills_dir" ] || return 0

  _dot_gstack_prune_legacy_unprefixed_codex "$skills_dir"

  while IFS= read -r dst; do
    base=$(basename "$dst")
    _dot_gstack_skill_dir_is_managed "$dst" || continue
    _dot_gstack_codex_skill_name_exists "$gstack_dir" "$base" && continue
    _dot_gstack_remove_skill_link "$dst"
  done < <(_dot_gstack_each_prefixed_skill_target "$skills_dir")
}

_dot_gstack_prune_stale_gemini() {
  local gstack_dir="$1" skills_dir="$2" dst base

  while IFS= read -r dst; do
    base=$(basename "$dst")
    _dot_gstack_skill_dir_is_managed "$dst" || continue
    _dot_gstack_codex_skill_name_exists "$gstack_dir" "$base" && continue
    _dot_gstack_remove_skill_link "$dst"
  done < <(_dot_gstack_each_prefixed_skill_target "$skills_dir")
}

# Link every registerable generated skill into a destination skills root. The
# Claude/Codex/Gemini register flows differ only in their destination root and
# agent-specific setup, so they share this final linking loop.
_dot_gstack_link_all_generated_into() {
  local dest_root="$1" gstack_dir="$2" i name link_name
  _dot_gstack_load_source_skills "$gstack_dir"
  for i in "${!_DOT_GSTACK_SOURCE_SKILL_NAMES[@]}"; do
    name="${_DOT_GSTACK_SOURCE_SKILL_NAMES[$i]}"
    link_name=$(_dot_gstack_codex_skill_name "$name")
    _dot_gstack_is_umbrella_link "$link_name" && continue
    _dot_gstack_link_generated_skill "$link_name" "$dest_root/$link_name"
  done
}

_dot_gstack_register_claude() {
  local gstack_dir="$1" skills_dir
  skills_dir="$(_dot_gstack_claude_skills_dir)"
  mkdir -p "$skills_dir"
  _dot_gstack_remove_skill_link "$skills_dir/gstack"
  _dot_gstack_remove_skill_link "$skills_dir/connect-chrome"

  _dot_gstack_prune_stale_claude "$gstack_dir" "$skills_dir"
  _dot_gstack_link_all_generated_into "$skills_dir" "$gstack_dir"
}

_dot_gstack_register_codex() {
  local gstack_dir="$1" skills_dir
  skills_dir="$(_dot_gstack_codex_skills_dir)"
  mkdir -p "$skills_dir"
  _dot_gstack_remove_skill_link "$skills_dir/gstack"
  _dot_gstack_prune_stale_codex "$gstack_dir" "$skills_dir"

  _dot_gstack_link_all_generated_into "$skills_dir" "$gstack_dir"
}

_dot_gstack_register_gemini() {
  local gstack_dir="$1" ext_dir
  ext_dir="$(_dot_gstack_gemini_extension_dir)"
  # A dangling symlink satisfies neither `-e` nor the managed check below, yet
  # `mkdir -p "$ext_dir/skills"` would try to create through the broken link and
  # fail. The managed extension is always a real directory, so clear a stale
  # symlink before any further checks.
  if [ -L "$ext_dir" ] && [ ! -e "$ext_dir" ]; then
    rm -f "$ext_dir"
  fi
  if [ -e "$ext_dir" ] && ! _dot_gstack_gemini_extension_is_managed "$ext_dir"; then
    _dot_gstack_warn "    warning: skipping unmanaged Gemini gstack extension at $ext_dir"
    return 0
  fi
  _dot_gstack_mark_managed_dir "$ext_dir"
  mkdir -p "$ext_dir/skills"
  _dot_gstack_prune_stale_gemini "$gstack_dir" "$ext_dir/skills"
  cat >"$ext_dir/gemini-extension.json" <<'JSON'
{
  "name": "gstack",
  "version": "1.0.0"
}
JSON
  ln -sfn "$(_dot_gstack_generated_skills_dir)/GEMINI.md" "$ext_dir/GEMINI.md"

  _dot_gstack_link_all_generated_into "$ext_dir/skills" "$gstack_dir"
}

_dot_gstack_unregister_generated_skills() {
  local generated_dir dst
  generated_dir=$(_dot_gstack_generated_skills_dir)

  while IFS= read -r dst; do
    _dot_gstack_remove_skill_link "$dst"
  done < <(_dot_gstack_each_prefixed_skill_target "$generated_dir")

  if [ -f "$generated_dir/GEMINI.md" ] &&
    grep -q '^<!-- dotfiles-managed-generator: dotfiles-gstack-gemini-context-' \
      "$generated_dir/GEMINI.md" 2>/dev/null; then
    rm -f "$generated_dir/GEMINI.md"
  fi
  rmdir "$generated_dir" 2>/dev/null || true
}

_dot_gstack_unregister_codex() {
  local gstack_dir="$1" skills_dir i name link_name
  skills_dir="$(_dot_gstack_codex_skills_dir)"
  if [ -d "$gstack_dir" ]; then
    _dot_gstack_load_source_skills "$gstack_dir"
    for i in "${!_DOT_GSTACK_SOURCE_SKILL_NAMES[@]}"; do
      name="${_DOT_GSTACK_SOURCE_SKILL_NAMES[$i]}"
      link_name=$(_dot_gstack_codex_skill_name "$name")
      _dot_gstack_remove_skill_link "$skills_dir/$link_name"
    done
  fi
  if _dot_gstack_codex_root_is_managed "$skills_dir/gstack"; then
    rm -rf "$skills_dir/gstack"
  fi
}

_dot_gstack_unregister_gemini() {
  local ext_dir
  ext_dir="$(_dot_gstack_gemini_extension_dir)"
  if _dot_gstack_gemini_extension_is_managed "$ext_dir"; then
    rm -rf "$ext_dir"
  fi
}
