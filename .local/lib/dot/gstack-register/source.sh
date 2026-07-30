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

_dot_gstack_load_skill_exclusions() {
  local file line
  file=$(_dot_gstack_skill_exclude_file)
  if [ "$_DOT_GSTACK_SKILL_EXCLUDE_LOADED" = "$file" ]; then
    return 0
  fi

  _DOT_GSTACK_SKILL_EXCLUDE_LOADED="$file"
  _DOT_GSTACK_SKILL_EXCLUDE=()
  [ -f "$file" ] || return 0

  # Tolerate a hand-edited file: strip comments and surrounding whitespace, and
  # accept a final line with no trailing newline. Entries are stored under the
  # normalized gstack-* link name so either spelling works in the file.
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -n "$line" ] || continue
    _DOT_GSTACK_SKILL_EXCLUDE["$(_dot_gstack_codex_skill_name "$line")"]=1
  done <"$file"
}

# Single owner of "which upstream directories are not registrable skills".
# The source scan and the cache watch-entry scan both consult this, so the two
# cannot drift apart and leave an excluded skill watched but unregistered.
#
# Matching is on the directory basename rather than the SKILL.md name field:
# the watch-entry pass runs on every warm `dot update` and must not pay a file
# read per directory. Upstream keeps the two in sync, and a mismatch fails open
# (the skill stays registered) rather than silently dropping something.
_dot_gstack_skill_dir_is_skipped() {
  local base="$1"
  case "$base" in
    node_modules | browser-skills | openclaw | test) return 0 ;;
  esac
  _dot_gstack_load_skill_exclusions
  [ -n "${_DOT_GSTACK_SKILL_EXCLUDE["$(_dot_gstack_codex_skill_name "$base")"]+x}" ]
}

# Exclusions are keyed by the normalized gstack-* link name, but upstream
# directories are normally unprefixed. Accept either spelling so the check
# stays correct if upstream ever ships an already-prefixed directory.
_dot_gstack_source_skill_dir_exists() {
  local gstack_dir="$1" link_name="$2"
  [ -f "$gstack_dir/$link_name/SKILL.md" ] && return 0
  [ -f "$gstack_dir/${link_name#gstack-}/SKILL.md" ]
}

_dot_gstack_each_source_skill() {
  local gstack_dir="$1" skill_dir base
  for skill_dir in "$gstack_dir"/*/; do
    [ -f "$skill_dir/SKILL.md" ] || continue
    base=$(basename "$skill_dir")
    _dot_gstack_skill_dir_is_skipped "$base" && continue
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
  # Load exclusions here, in the parent shell. The scan below reads from a
  # process substitution, so anything _dot_gstack_each_source_skill populates
  # lives only in that subshell and would be invisible to the warning check.
  _dot_gstack_load_skill_exclusions

  while IFS= read -r skill_dir; do
    [ -n "$skill_dir" ] || continue
    name=$(_dot_gstack_skill_name "$skill_dir")
    _DOT_GSTACK_SOURCE_SKILL_DIRS+=("$skill_dir")
    _DOT_GSTACK_SOURCE_SKILL_NAMES+=("$name")
    _DOT_GSTACK_SOURCE_NAME_EXISTS["$name"]=1
    _DOT_GSTACK_SOURCE_CODEX_NAME_EXISTS["$(_dot_gstack_codex_skill_name "$name")"]=1
  done < <(_dot_gstack_each_source_skill "$gstack_dir")

  _dot_gstack_warn_unmatched_skill_exclusions "$gstack_dir"
}

# An exclusion that matches no upstream directory is almost always a typo, and
# it fails open, so the skill stays registered and the user sees no effect.
# Warn once per scan rather than letting the list rot silently.
_dot_gstack_warn_unmatched_skill_exclusions() {
  local gstack_dir="$1" name joined unmatched=()
  for name in "${!_DOT_GSTACK_SKILL_EXCLUDE[@]}"; do
    _dot_gstack_source_skill_dir_exists "$gstack_dir" "$name" && continue
    unmatched+=("$name")
  done
  [ "${#unmatched[@]}" -gt 0 ] || return 0

  # Sort for a stable message; associative-array key order is unspecified.
  joined=$(printf '%s\n' "${unmatched[@]}" | LC_ALL=C sort | tr '\n' ' ')
  _dot_gstack_warn \
    "gstack: exclusion matched no upstream skill: ${joined% } ($(_dot_gstack_skill_exclude_file))"
}

_dot_gstack_reset_source_cache() {
  _DOT_GSTACK_SOURCE_CACHE_DIR=''
  _DOT_GSTACK_SOURCE_SKILL_DIRS=()
  _DOT_GSTACK_SOURCE_SKILL_NAMES=()
  _DOT_GSTACK_SOURCE_NAME_EXISTS=()
  _DOT_GSTACK_SOURCE_CODEX_NAME_EXISTS=()
  _DOT_GSTACK_SKILL_EXCLUDE_LOADED=''
  _DOT_GSTACK_SKILL_EXCLUDE=()
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
