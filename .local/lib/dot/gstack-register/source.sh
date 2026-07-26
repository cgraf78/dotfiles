# shellcheck shell=bash
# Source skill inventory for the upstream gstack checkout.
#
# Registration work needs a stable view of source skills across generated
# files, target links, and cache fingerprints. Cache the scan per checkout so a
# single dot update does not repeatedly walk the same source tree.

_dot_gstack_skill_name() {
  local skill_dir="$1" name
  name=$(
    sed -n 's/^name:[[:space:]]*//p' "$skill_dir/SKILL.md" 2>/dev/null |
      head -1 |
      tr -d '[:space:]'
  )
  if [ -n "$name" ]; then
    printf '%s\n' "$name"
  else
    basename "$skill_dir"
  fi
}

_dot_gstack_each_source_skill() {
  local gstack_dir="$1" skill_dir base
  for skill_dir in "$gstack_dir"/*/; do
    [ -f "$skill_dir/SKILL.md" ] || continue
    base=$(basename "$skill_dir")
    case "$base" in
      node_modules | browser-skills | openclaw | test) continue ;;
    esac
    printf '%s\n' "${skill_dir%/}"
  done
}

_dot_gstack_load_source_skills() {
  local gstack_dir="$1" skill_dir name
  if [ "$_DOT_GSTACK_SOURCE_CACHE_DIR" = "$gstack_dir" ]; then
    return 0
  fi

  _DOT_GSTACK_SOURCE_CACHE_DIR="$gstack_dir"
  _DOT_GSTACK_SOURCE_SKILL_DIRS=()
  _DOT_GSTACK_SOURCE_SKILL_NAMES=()
  _DOT_GSTACK_SOURCE_NAME_EXISTS=()
  _DOT_GSTACK_SOURCE_CODEX_NAME_EXISTS=()

  while IFS= read -r skill_dir; do
    [ -n "$skill_dir" ] || continue
    name=$(_dot_gstack_skill_name "$skill_dir")
    _DOT_GSTACK_SOURCE_SKILL_DIRS+=("$skill_dir")
    _DOT_GSTACK_SOURCE_SKILL_NAMES+=("$name")
    _DOT_GSTACK_SOURCE_NAME_EXISTS["$name"]=1
    _DOT_GSTACK_SOURCE_CODEX_NAME_EXISTS["$(_dot_gstack_codex_skill_name "$name")"]=1
  done < <(_dot_gstack_each_source_skill "$gstack_dir")
}

_dot_gstack_reset_source_cache() {
  _DOT_GSTACK_SOURCE_CACHE_DIR=''
  _DOT_GSTACK_SOURCE_SKILL_DIRS=()
  _DOT_GSTACK_SOURCE_SKILL_NAMES=()
  _DOT_GSTACK_SOURCE_NAME_EXISTS=()
  _DOT_GSTACK_SOURCE_CODEX_NAME_EXISTS=()
}

_dot_gstack_is_prefixed_skill_name() {
  case "$1" in
    gstack-*) return 0 ;;
    *) return 1 ;;
  esac
}

_dot_gstack_codex_skill_name() {
  if _dot_gstack_is_prefixed_skill_name "$1"; then
    printf '%s\n' "$1"
  else
    printf 'gstack-%s\n' "$1"
  fi
}

_dot_gstack_each_prefixed_skill_target() {
  local skills_dir="$1" dst
  [ -d "$skills_dir" ] || return 0

  # The gstack-* namespace is how dotfiles distinguishes generated agent skills
  # from unrelated user-installed skills. Keep the filesystem discovery contract
  # beside the name-normalization policy so cleanup and cache code cannot drift.
  for dst in "$skills_dir"/gstack-*; do
    [ -e "$dst" ] || [ -L "$dst" ] || continue
    printf '%s\n' "$dst"
  done
}

# The upstream root "gstack" skill maps to the link name "gstack-gstack".
# dotfiles treats it as the umbrella rather than a child skill, so it is never
# linked, generated, fingerprinted, or watched as a registration target. This
# is the single owner of that rule; every registration loop consults it instead
# of retyping the literal.
_dot_gstack_is_umbrella_link() {
  [ "$1" = "gstack-gstack" ]
}

_dot_gstack_codex_skill_name_exists() {
  local gstack_dir="$1" expected="$2"
  _dot_gstack_load_source_skills "$gstack_dir"
  [ -n "${_DOT_GSTACK_SOURCE_CODEX_NAME_EXISTS[$expected]+x}" ]
}
