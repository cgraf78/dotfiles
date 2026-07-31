# shellcheck shell=bash
# Managed-target detection and safe removal helpers.
#
# These checks are intentionally conservative. Dotfiles can remove directories
# it created or old gstack-shaped links it knows how to recognize, but it must
# preserve unrelated user-installed skills even when names collide.

_dot_gstack_remove_link_if_managed() {
  local dst="$1" link_dest
  [ -L "$dst" ] || return 0
  link_dest=$(readlink "$dst" 2>/dev/null || true)
  _dot_gstack_points_to_managed_gstack "$link_dest" && rm -f "$dst"
}

_dot_gstack_points_to_gstack() {
  case "$1" in
    gstack/* | */garrytan/gstack | */garrytan/gstack/*) return 0 ;;
  esac

  return 1
}

_dot_gstack_points_to_dotfiles_skills() {
  local generated_dir opencode_generated_dir
  generated_dir=$(_dot_gstack_generated_skills_dir)
  opencode_generated_dir=$(_dot_gstack_opencode_generated_skills_dir)
  case "$1" in
    "$generated_dir" | "$generated_dir"/* | .gstack/dotfiles-skills | .gstack/dotfiles-skills/* | \
      */.gstack/dotfiles-skills | */.gstack/dotfiles-skills/* | \
      "$opencode_generated_dir" | "$opencode_generated_dir"/* | \
      .gstack/dotfiles-opencode-skills | .gstack/dotfiles-opencode-skills/* | \
      */.gstack/dotfiles-opencode-skills | */.gstack/dotfiles-opencode-skills/*)
      return 0
      ;;
  esac

  return 1
}

_dot_gstack_points_to_managed_gstack() {
  _dot_gstack_points_to_gstack "$1" || _dot_gstack_points_to_dotfiles_skills "$1"
}

_dot_gstack_managed_marker() {
  printf '%s\n' "$1/.dotfiles-managed-gstack"
}

_dot_gstack_mark_managed_dir() {
  local dir="$1"
  mkdir -p "$dir"
  : >"$(_dot_gstack_managed_marker "$dir")"
}

_dot_gstack_codex_root_is_managed() {
  local root="$1" skill_link
  [ -d "$root" ] || return 1
  [ -f "$(_dot_gstack_managed_marker "$root")" ] && return 0

  skill_link=$(readlink "$root/SKILL.md" 2>/dev/null || true)
  case "$skill_link" in
    */garrytan/gstack/SKILL.md) return 0 ;;
  esac

  return 1
}

_dot_gstack_gemini_extension_is_managed() {
  local ext_dir="$1" skill_link
  [ -d "$ext_dir" ] || return 1
  [ -f "$(_dot_gstack_managed_marker "$ext_dir")" ] && return 0

  skill_link=$(readlink "$ext_dir/GEMINI.md" 2>/dev/null || true)
  _dot_gstack_points_to_managed_gstack "$skill_link" && return 0

  if [ -d "$ext_dir/skills" ] &&
    grep -q '^<!-- dotfiles-managed-source: .*/garrytan/gstack/.*/SKILL.md -->$' \
      "$ext_dir"/skills/*/SKILL.md 2>/dev/null; then
    return 0
  fi

  return 1
}

_dot_gstack_opencode_root_is_managed() {
  local root="$1" skill_link
  [ -d "$root" ] || return 1
  [ -f "$(_dot_gstack_managed_marker "$root")" ] && return 0

  skill_link=$(readlink "$root/SKILL.md" 2>/dev/null || true)
  _dot_gstack_points_to_managed_gstack "$skill_link"
}

_dot_gstack_skill_dir_is_managed() {
  local dst="$1" link_dest
  if [ -L "$dst" ]; then
    link_dest=$(readlink "$dst" 2>/dev/null || true)
    _dot_gstack_points_to_managed_gstack "$link_dest"
    return
  fi

  if [ -d "$dst" ] && [ -f "$(_dot_gstack_managed_marker "$dst")" ]; then
    return 0
  fi

  if [ -d "$dst" ] && [ -L "$dst/SKILL.md" ]; then
    link_dest=$(readlink "$dst/SKILL.md" 2>/dev/null || true)
    _dot_gstack_points_to_managed_gstack "$link_dest"
    return
  fi

  if [ -d "$dst" ] && [ -f "$dst/SKILL.md" ] &&
    grep -q '^<!-- dotfiles-managed-source: .*/garrytan/gstack/.*/SKILL.md -->$' "$dst/SKILL.md" 2>/dev/null; then
    return 0
  fi

  return 1
}

_dot_gstack_remove_skill_link() {
  local dst="$1" link_dest
  if [ -L "$dst" ]; then
    link_dest=$(readlink "$dst" 2>/dev/null || true)
    _dot_gstack_points_to_managed_gstack "$link_dest" && rm -f "$dst"
  elif [ -d "$dst" ] && [ -L "$dst/SKILL.md" ]; then
    link_dest=$(readlink "$dst/SKILL.md" 2>/dev/null || true)
    _dot_gstack_points_to_managed_gstack "$link_dest" && rm -rf "$dst"
  elif [ -d "$dst" ] && [ -f "$(_dot_gstack_managed_marker "$dst")" ]; then
    rm -rf "$dst"
  elif [ -d "$dst" ] && [ -f "$dst/SKILL.md" ] &&
    grep -q '^<!-- dotfiles-managed-source: .*/garrytan/gstack/.*/SKILL.md -->$' "$dst/SKILL.md" 2>/dev/null; then
    rm -rf "$dst"
  fi
}
