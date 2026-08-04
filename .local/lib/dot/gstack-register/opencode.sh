# shellcheck shell=bash
# Dependency-free OpenCode skill transformation and registration.
#
# Upstream's native OpenCode artifacts require Bun and are not committed. This
# module mirrors the stable host contract with Bash/Awk: allowlisted frontmatter,
# OpenCode runtime paths, the root router, and the required runtime assets.

_dot_gstack_opencode_name_is_codex() {
  case "$1" in
    codex | gstack-codex) return 0 ;;
  esac
  return 1
}

_dot_gstack_opencode_routing_description() {
  local skill_md="$1"
  awk '
    function append(current, value) {
      return current == "" ? value : current " " value
    }
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    NR == 1 && $0 == "---" {
      in_frontmatter = 1
      next
    }
    in_frontmatter && $0 == "---" {
      in_frontmatter = 0
      in_description_block = 0
      next
    }
    in_frontmatter && $0 ~ /^description:[[:space:]]*/ {
      value = $0
      sub(/^description:[[:space:]]*/, "", value)
      in_description_block = value ~ /^[|>][-+]?$/
      if (!in_description_block) description = trim(value)
      next
    }
    in_frontmatter && in_description_block && ($0 == "" || $0 ~ /^[[:space:]]/) {
      value = trim($0)
      if (value != "") description = append(description, value)
      next
    }
    in_frontmatter {
      in_description_block = 0
      next
    }
    $0 == "## When to invoke this skill" {
      in_routing = 1
      next
    }
    in_routing && $0 ~ /^##[[:space:]]/ {
      in_routing = 0
    }
    in_routing {
      value = trim($0)
      if (value != "") routing = append(routing, value)
    }
    END {
      double_quote = sprintf("%c", 34)
      single_quote = sprintf("%c", 39)
      if (substr(description, 1, 1) == double_quote &&
        substr(description, length(description), 1) == double_quote) {
        description = substr(description, 2, length(description) - 2)
      } else if (substr(description, 1, 1) == single_quote &&
        substr(description, length(description), 1) == single_quote) {
        description = substr(description, 2, length(description) - 2)
      }
      has_suffix = description ~ /[[:space:]]*[(]gstack[)][[:space:]]*$/
      sub(/[[:space:]]*[(]gstack[)][[:space:]]*$/, "", description)
      output = description
      if (routing != "") output = append(output, routing)
      if (has_suffix) output = append(output, "(gstack)")
      print output
    }
  ' "$skill_md"
}

_dot_gstack_write_opencode_skill_md() {
  local src="$1" dst="$2" name="$3" runtime_root="$4"
  local skills_root full_description tmp
  skills_root=$(_dot_gstack_opencode_skills_dir)
  full_description=$(_dot_gstack_opencode_routing_description "$src/SKILL.md") || return 1

  if { [ -e "$dst" ] || [ -L "$dst" ]; } &&
    ! _dot_gstack_skill_dir_is_managed "$dst"; then
    _dot_gstack_warn "    warning: skipping unmanaged generated OpenCode skill at $dst"
    return 1
  fi
  if [ -L "$dst" ]; then
    rm -f "$dst" || return 1
  fi
  _dot_gstack_mark_managed_dir "$dst" || return 1
  _dot_sibling_tmp_for "$dst/SKILL.md" || return 1
  tmp="$REPLY"

  awk -v new_name="$name" -v source="$src/SKILL.md" \
    -v runtime_root="$runtime_root" -v skills_root="$skills_root" \
    -v full_description="$full_description" \
    -v generator="$_DOT_GSTACK_OPENCODE_SKILL_VERSION" '
    function rewrite_runtime_paths(line) {
      gsub(/~\/[.]claude\/skills\/gstack/, runtime_root, line)
      gsub(/[$]HOME\/[.]claude\/skills\/gstack/, runtime_root, line)
      gsub(/[$][{]HOME[}]\/[.]claude\/skills\/gstack/, runtime_root, line)
      gsub(/~\/[.]claude\/skills\/review/, runtime_root "/review", line)
      gsub(/[$]HOME\/[.]claude\/skills\/review/, runtime_root "/review", line)
      gsub(/[$][{]HOME[}]\/[.]claude\/skills\/review/, runtime_root "/review", line)
      gsub(/~\/[.]claude\/skills/, skills_root, line)
      gsub(/[$]HOME\/[.]claude\/skills/, skills_root, line)
      gsub(/[$][{]HOME[}]\/[.]claude\/skills/, skills_root, line)
      return line
    }
    BEGIN {
      in_frontmatter = 0
    }
    NR == 1 && $0 == "---" {
      in_frontmatter = 1
      print
      next
    }
    in_frontmatter && $0 == "---" {
      print "name: " new_name
      print "description: |"
      print "  " rewrite_runtime_paths(full_description)
      print
      print "<!-- dotfiles-managed-source: " source " -->"
      print "<!-- dotfiles-managed-generator: " generator " -->"
      in_frontmatter = 0
      next
    }
    in_frontmatter {
      next
    }
    { print rewrite_runtime_paths($0) }
  ' "$src/SKILL.md" >"$tmp" || {
    rm -f "$tmp"
    return 1
  }

  if [ -f "$dst/SKILL.md" ] && cmp -s "$tmp" "$dst/SKILL.md"; then
    rm -f "$tmp"
  else
    mv "$tmp" "$dst/SKILL.md" || {
      rm -f "$tmp"
      return 1
    }
  fi
}

_dot_gstack_prune_stale_opencode_generated() {
  local gstack_dir="$1" generated_dir="$2" dst base rc=0
  while IFS= read -r dst; do
    base=$(basename "$dst")
    [ "$base" = "gstack" ] && continue
    if [ "$base" != "gstack-codex" ] &&
      _dot_gstack_codex_skill_name_exists "$gstack_dir" "$base"; then
      continue
    fi
    _dot_gstack_skill_dir_is_managed "$dst" || continue
    _dot_gstack_remove_skill_link "$dst" || rc=1
  done < <(_dot_gstack_each_prefixed_skill_target "$generated_dir")
  return "$rc"
}

_dot_gstack_write_opencode_skills() {
  local gstack_dir="$1" generated_dir runtime_root i skill_dir source_base name
  local link_name skill_name rc=0
  generated_dir=$(_dot_gstack_opencode_generated_skills_dir)
  runtime_root="$(_dot_gstack_opencode_skills_dir)/gstack"
  _dot_gstack_mark_managed_dir "$generated_dir" || return 1

  _dot_gstack_write_opencode_skill_md "$gstack_dir" "$generated_dir/gstack" \
    "gstack" "$runtime_root" || rc=1

  _dot_gstack_load_source_skills "$gstack_dir"
  for i in "${!_DOT_GSTACK_SOURCE_SKILL_DIRS[@]}"; do
    skill_dir="${_DOT_GSTACK_SOURCE_SKILL_DIRS[$i]}"
    source_base=$(basename "$skill_dir")
    name="${_DOT_GSTACK_SOURCE_SKILL_NAMES[$i]}"
    if [ "$source_base" = "codex" ] ||
      _dot_gstack_opencode_name_is_codex "$name"; then
      continue
    fi
    link_name=$(_dot_gstack_codex_skill_name "$name")
    _dot_gstack_is_umbrella_link "$link_name" && continue

    skill_name="$name"
    if [ "$name" = "gstack-$source_base" ] && [ "$source_base" != "gstack" ]; then
      skill_name="$source_base"
    fi
    _dot_gstack_write_opencode_skill_md "$skill_dir" "$generated_dir/$link_name" \
      "$skill_name" "$runtime_root" || rc=1
  done

  _dot_gstack_prune_stale_opencode_generated "$gstack_dir" "$generated_dir" || rc=1
  return "$rc"
}

_dot_gstack_each_opencode_runtime_asset() {
  local gstack_dir="$1" generated_dir source rel file
  generated_dir=$(_dot_gstack_opencode_generated_skills_dir)

  for rel in \
    bin \
    browse/dist \
    browse/bin \
    design/dist \
    review/specialists \
    qa/templates \
    qa/references; do
    source="$gstack_dir/$rel"
    [ -e "$source" ] || [ -L "$source" ] || continue
    printf '%s\t%s\n' "$source" "$rel"
  done

  source="$generated_dir/gstack/SKILL.md"
  [ -f "$source" ] && printf '%s\t%s\n' "$source" "SKILL.md"
  source="$generated_dir/gstack-upgrade/SKILL.md"
  [ -f "$source" ] && printf '%s\t%s\n' "$source" "gstack-upgrade/SKILL.md"

  for file in checklist.md design-checklist.md greptile-triage.md TODOS-format.md; do
    source="$gstack_dir/review/$file"
    [ -f "$source" ] && printf '%s\t%s\n' "$source" "review/$file"
  done

  for rel in plan-devex-review/dx-hall-of-fame.md ETHOS.md; do
    source="$gstack_dir/$rel"
    [ -f "$source" ] && printf '%s\t%s\n' "$source" "$rel"
  done
}

_dot_gstack_link_opencode_runtime_asset() {
  local root="$1" source="$2" rel="$3" dst
  dst="$root/$rel"
  mkdir -p "$(dirname "$dst")" || return 1
  rm -rf "$dst" || return 1
  ln -s "$source" "$dst"
}

_dot_gstack_clear_opencode_runtime_assets() {
  local root="$1" rel rc=0
  [ -n "$root" ] || return 1
  for rel in SKILL.md bin browse design gstack-upgrade review qa plan-devex-review ETHOS.md; do
    rm -rf "${root:?}/$rel" || rc=1
  done
  return "$rc"
}

_dot_gstack_prune_stale_opencode() {
  local skills_dir="$1" generated_dir dst base rc=0
  generated_dir=$(_dot_gstack_opencode_generated_skills_dir)
  while IFS= read -r dst; do
    base=$(basename "$dst")
    [ -f "$generated_dir/$base/SKILL.md" ] && continue
    _dot_gstack_skill_dir_is_managed "$dst" || continue
    _dot_gstack_remove_skill_link "$dst" || rc=1
  done < <(_dot_gstack_each_prefixed_skill_target "$skills_dir")
  return "$rc"
}

_dot_gstack_link_opencode_skills() {
  local skills_dir="$1" generated_dir skill_dir link_name dst rc=0
  generated_dir=$(_dot_gstack_opencode_generated_skills_dir)
  for skill_dir in "$generated_dir"/gstack-*/; do
    [ -f "$skill_dir/SKILL.md" ] || continue
    link_name=$(basename "$skill_dir")
    dst="$skills_dir/$link_name"
    if { [ -e "$dst" ] || [ -L "$dst" ]; } &&
      ! _dot_gstack_skill_dir_is_managed "$dst"; then
      _dot_gstack_warn "    warning: skipping unmanaged OpenCode skill at $dst"
      continue
    fi
    _dot_gstack_remove_skill_link "$dst" || rc=1
    ln -s "${skill_dir%/}" "$dst" || rc=1
  done
  return "$rc"
}

_dot_gstack_register_opencode() {
  local gstack_dir="$1" skills_dir root source rel rc=0
  skills_dir=$(_dot_gstack_opencode_skills_dir)
  root="$skills_dir/gstack"

  if { [ -e "$root" ] || [ -L "$root" ]; } &&
    ! _dot_gstack_opencode_root_is_managed "$root"; then
    _dot_gstack_warn "    warning: skipping unmanaged OpenCode gstack root at $root"
    return 0
  fi

  _dot_gstack_write_opencode_skills "$gstack_dir" || return 1
  mkdir -p "$skills_dir" || return 1
  _dot_gstack_mark_managed_dir "$root" || return 1
  _dot_gstack_clear_opencode_runtime_assets "$root" || rc=1
  while IFS=$'\t' read -r source rel; do
    [ -n "$source" ] || continue
    _dot_gstack_link_opencode_runtime_asset "$root" "$source" "$rel" || rc=1
  done < <(_dot_gstack_each_opencode_runtime_asset "$gstack_dir")

  _dot_gstack_prune_stale_opencode "$skills_dir" || rc=1
  _dot_gstack_link_opencode_skills "$skills_dir" || rc=1
  return "$rc"
}

_dot_gstack_unregister_opencode_generated() {
  local generated_dir
  generated_dir=$(_dot_gstack_opencode_generated_skills_dir)
  if [ -d "$generated_dir" ] &&
    [ -f "$(_dot_gstack_managed_marker "$generated_dir")" ]; then
    rm -rf "$generated_dir"
  fi
}

_dot_gstack_unregister_opencode() {
  local skills_dir root dst rc=0
  skills_dir=$(_dot_gstack_opencode_skills_dir)
  root="$skills_dir/gstack"

  if { [ -e "$root" ] || [ -L "$root" ]; } &&
    ! _dot_gstack_opencode_root_is_managed "$root"; then
    return 0
  fi

  while IFS= read -r dst; do
    _dot_gstack_remove_skill_link "$dst" || rc=1
  done < <(_dot_gstack_each_prefixed_skill_target "$skills_dir")

  if _dot_gstack_opencode_root_is_managed "$root"; then
    rm -rf "$root" || rc=1
  fi
  _dot_gstack_unregister_opencode_generated || rc=1
  return "$rc"
}
