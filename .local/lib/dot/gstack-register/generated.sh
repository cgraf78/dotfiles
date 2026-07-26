# shellcheck shell=bash
# Generated gstack skill materialization.
#
# Dotfiles registers generated skills rather than linking upstream skills
# directly because Codex/Gemini need gstack-prefixed names and all agents need
# legacy Claude runtime paths rewritten to the real checkout.

_dot_gstack_link_generated_skill() {
  local name="$1" dst="$2" src
  src="$(_dot_gstack_generated_skills_dir)/$name"

  if [ ! -d "$src" ]; then
    _dot_gstack_warn "    warning: generated gstack skill missing at $src"
    return 1
  fi

  if { [ -e "$dst" ] || [ -L "$dst" ]; } && ! _dot_gstack_skill_dir_is_managed "$dst"; then
    _dot_gstack_warn "    warning: skipping unmanaged skill at $dst"
    return 0
  fi

  rm -rf "$dst"
  ln -sfn "$src" "$dst"
}

_dot_gstack_generated_skill_current() {
  local src="$1" dst="$2" name="$3"
  local skill_md="$dst/SKILL.md"
  local source_marker="<!-- dotfiles-managed-source: $src/SKILL.md -->"
  local version_marker="<!-- dotfiles-managed-generator: $_DOT_GSTACK_GENERATED_SKILL_VERSION -->"
  local found_name='' found_source='' found_version='' line

  [ -f "$skill_md" ] || return 1
  [ "$skill_md" -nt "$src/SKILL.md" ] || return 1

  while IFS= read -r line || [ -n "$line" ]; do
    [ "$line" = "name: $name" ] && found_name=1
    [ "$line" = "$source_marker" ] && found_source=1
    [ "$line" = "$version_marker" ] && found_version=1
    if [ -n "$found_name" ] && [ -n "$found_source" ] && [ -n "$found_version" ]; then
      return 0
    fi
  done <"$skill_md"

  return 1
}

_dot_gstack_write_skill_md() {
  local src="$1" dst="$2" name="$3" runtime_root="${4:-}" tmp
  [ -n "$runtime_root" ] || runtime_root=$(dot_gstack_dir)
  if [ -e "$dst" ] && ! _dot_gstack_skill_dir_is_managed "$dst"; then
    _dot_gstack_warn "    warning: skipping unmanaged skill at $dst"
    return 0
  fi
  if [ -L "$dst" ]; then
    rm -f "$dst"
  fi
  mkdir -p "$dst"
  _dot_gstack_mark_managed_dir "$dst"
  if _dot_gstack_generated_skill_current "$src" "$dst" "$name"; then
    return 0
  fi

  _dot_sibling_tmp_for "$dst/SKILL.md" || return 1
  tmp="$REPLY"
  awk -v new_name="$name" -v source="$src/SKILL.md" -v runtime_root="$runtime_root" \
    -v generator="$_DOT_GSTACK_GENERATED_SKILL_VERSION" '
    function yaml_double_quote(value) {
      gsub(/\\/, "\\\\", value)
      gsub(/"/, "\\\"", value)
      return "\"" value "\""
    }
    function rewrite_runtime_paths(line) {
      gsub(/~\/[.]claude\/skills\/gstack/, runtime_root, line)
      gsub(/[$]HOME\/[.]claude\/skills\/gstack/, runtime_root, line)
      gsub(/[$][{]HOME[}]\/[.]claude\/skills\/gstack/, runtime_root, line)
      return line
    }
    BEGIN { in_frontmatter = 0; replaced = 0 }
    NR == 1 && $0 == "---" {
      in_frontmatter = 1
      print rewrite_runtime_paths($0)
      next
    }
    in_frontmatter && $0 ~ /^name:[[:space:]]*/ && replaced == 0 {
      print "name: " new_name
      replaced = 1
      next
    }
    in_frontmatter && $0 ~ /^description:[[:space:]]*/ {
      value = $0
      sub(/^description:[[:space:]]*/, "", value)
      if (value !~ /^(["\047|>]|$)/ && value ~ /:[[:space:]]/) {
        print "description: " yaml_double_quote(value)
        next
      }
    }
    in_frontmatter && $0 == "---" {
      if (replaced == 0) {
        print "name: " new_name
        replaced = 1
      }
      print rewrite_runtime_paths($0)
      print "<!-- dotfiles-managed-source: " source " -->"
      print "<!-- dotfiles-managed-generator: " generator " -->"
      in_frontmatter = 0
      next
    }
    { print rewrite_runtime_paths($0) }
  ' "$src/SKILL.md" >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  if [ -f "$dst/SKILL.md" ] && cmp -s "$tmp" "$dst/SKILL.md"; then
    rm -f "$tmp"
    # Content is unchanged, but the freshness gate (_dot_gstack_generated_skill_current)
    # requires dst to be strictly newer than src (`-nt`). Bump the destination to
    # now so the next run sees it as current; otherwise an older-but-identical dst
    # regenerates forever.
    touch "$dst/SKILL.md"
  else
    mv "$tmp" "$dst/SKILL.md" || {
      rm -f "$tmp"
      return 1
    }
  fi
}
_dot_gstack_prune_stale_generated_skills() {
  local gstack_dir="$1" generated_dir dst base
  generated_dir=$(_dot_gstack_generated_skills_dir)

  _dot_gstack_load_source_skills "$gstack_dir"
  while IFS= read -r dst; do
    base=$(basename "$dst")
    _dot_gstack_skill_dir_is_managed "$dst" || continue
    _dot_gstack_codex_skill_name_exists "$gstack_dir" "$base" && continue
    _dot_gstack_remove_skill_link "$dst"
  done < <(_dot_gstack_each_prefixed_skill_target "$generated_dir")
}

_dot_gstack_write_gemini_context() {
  local gstack_dir="$1" generated_dir dst tmp
  generated_dir=$(_dot_gstack_generated_skills_dir)
  dst="$generated_dir/GEMINI.md"
  mkdir -p "$generated_dir"
  _dot_sibling_tmp_for "$dst" || return 1
  tmp="$REPLY"
  cat >"$tmp" <<EOF
# gstack

Dotfiles registers gstack for Gemini through the generated \`gstack-*\` agent
skills in this extension. Runtime assets live in:

\`$gstack_dir\`

<!-- dotfiles-managed-source: $gstack_dir/SKILL.md -->
<!-- dotfiles-managed-generator: $_DOT_GSTACK_GEMINI_CONTEXT_VERSION -->
EOF
  if [ -f "$dst" ] && cmp -s "$tmp" "$dst"; then
    rm -f "$tmp"
  else
    mv "$tmp" "$dst" || {
      rm -f "$tmp"
      return 1
    }
  fi
}

_dot_gstack_write_generated_skills() {
  local gstack_dir="$1" generated_dir i skill_dir name link_name
  generated_dir=$(_dot_gstack_generated_skills_dir)

  mkdir -p "$generated_dir"
  _dot_gstack_write_gemini_context "$gstack_dir"
  _dot_gstack_prune_stale_generated_skills "$gstack_dir"
  _dot_gstack_load_source_skills "$gstack_dir"
  for i in "${!_DOT_GSTACK_SOURCE_SKILL_DIRS[@]}"; do
    skill_dir="${_DOT_GSTACK_SOURCE_SKILL_DIRS[$i]}"
    name="${_DOT_GSTACK_SOURCE_SKILL_NAMES[$i]}"
    link_name=$(_dot_gstack_codex_skill_name "$name")
    _dot_gstack_is_umbrella_link "$link_name" && continue
    _dot_gstack_write_skill_md "$skill_dir" "$generated_dir/$link_name" "$link_name" "$gstack_dir"
  done
}
