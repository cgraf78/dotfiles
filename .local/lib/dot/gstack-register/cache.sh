# shellcheck shell=bash
# Registration cache and fast-path invalidation.
#
# Warm dot update runs frequently, so the cache avoids rewriting every generated
# skill when source and target trees are unchanged. Watch entries are mtime
# guards; when anything is newer or missing, the slower fingerprint path still
# validates and repairs the managed tree.

_dot_gstack_source_fingerprint() {
  local gstack_dir="$1" skill_dir rel name sum asset

  {
    # The source fingerprint captures every input that can change what the
    # registration step should produce. Agent availability is included because
    # losing Codex/Gemini/OpenCode should remove registrations for that agent,
    # while gaining one should create them on the next dot update.
    printf 'version\t%s\n' "$_DOT_GSTACK_REGISTRATION_CACHE_VERSION"
    # The exclude list is a registration input even though it lives outside the
    # checkout; hash it so a content edit invalidates the cache even when the
    # file mtime-based watch entry cannot (for example after a restore).
    printf 'exclude\t%s\n' "$(_dot_gstack_cksum_file "$(_dot_gstack_skill_exclude_file)")"
    for asset in SKILL.md bin browse review qa ETHOS.md; do
      if [ -e "$gstack_dir/$asset" ]; then
        if [ -f "$gstack_dir/$asset" ]; then
          printf 'asset\t%s\tfile\t%s\n' "$asset" "$(_dot_gstack_cksum_file "$gstack_dir/$asset")"
        elif [ -d "$gstack_dir/$asset" ]; then
          printf 'asset\t%s\tdir\n' "$asset"
        elif [ -L "$gstack_dir/$asset" ]; then
          printf 'asset\t%s\tlink\t%s\n' "$asset" "$(readlink "$gstack_dir/$asset" 2>/dev/null || true)"
        else
          printf 'asset\t%s\tother\n' "$asset"
        fi
      else
        printf 'asset\t%s\tmissing\n' "$asset"
      fi
    done
    printf 'agent\tclaude\t%s\n' "$(
      _dot_gstack_has_agent claude
      printf '%s' "$?"
    )"
    printf 'agent\tcodex\t%s\n' "$(
      _dot_gstack_has_agent codex
      printf '%s' "$?"
    )"
    printf 'agent\tgemini\t%s\n' "$(
      _dot_gstack_has_agent gemini
      printf '%s' "$?"
    )"
    printf 'agent\topencode\t%s\n' "$(
      _dot_gstack_has_agent opencode
      printf '%s' "$?"
    )"

    while IFS= read -r skill_dir; do
      [ -n "$skill_dir" ] || continue
      rel="${skill_dir#"$gstack_dir"/}"
      name=$(_dot_gstack_skill_name "$skill_dir")
      sum=$(_dot_gstack_cksum_file "$skill_dir/SKILL.md")
      printf 'skill\t%s\t%s\t%s\n' "$rel" "$name" "$sum"
    done < <(_dot_gstack_each_source_skill "$gstack_dir" | LC_ALL=C sort)
  } | _dot_gstack_hash_stream
}

_dot_gstack_emit_target_entry() {
  local path="$1" label="$2"
  if [ -L "$path" ]; then
    printf 'target\t%s\tlink\t%s\t%s\n' "$label" "$path" "$(readlink "$path" 2>/dev/null || true)"
  elif [ -f "$path" ]; then
    # Target files are generated or tiny markers; hashing every generated copy
    # dominated the warm `dot update` path without buying byte-for-byte repair.
    # Full registration already validates generated skill name/source/generator
    # markers rather than arbitrary prose edits. For cache safety we need the
    # structural fact that the file exists, plus a cheap mtime guard so edits
    # after the cache was written still force the full validation path.
    if [ -n "${_DOT_GSTACK_TARGET_FRESHNESS_CACHE_FILE:-}" ] &&
      [ "$path" -nt "$_DOT_GSTACK_TARGET_FRESHNESS_CACHE_FILE" ]; then
      printf 'target\t%s\tfile-newer-than-cache\t%s\n' "$label" "$path"
    else
      printf 'target\t%s\tfile\t%s\n' "$label" "$path"
    fi
  elif [ -d "$path" ]; then
    printf 'target\t%s\tdir\t%s\n' "$label" "$path"
  elif [ -e "$path" ]; then
    printf 'target\t%s\tother\t%s\n' "$label" "$path"
  else
    printf 'target\t%s\tmissing\t%s\n' "$label" "$path"
  fi
}

_dot_gstack_emit_unexpected_managed_targets() {
  local gstack_dir="$1" generated_dir="$2" claude_dir="$3" codex_dir="$4" gemini_skill_dir="$5"
  local opencode_dir="$6"
  local opencode_generated_dir dst base
  opencode_generated_dir=$(_dot_gstack_opencode_generated_skills_dir)

  # Expected-output fingerprints catch missing generated files, but they do not
  # naturally notice extra managed directories left behind after a source skill
  # is removed or renamed. Scan only the immediate skill roots and only emit
  # entries for targets dotfiles owns. That preserves `dot update` as a cleanup
  # path without hashing every unrelated user-installed skill on every run.
  _dot_gstack_load_source_skills "$gstack_dir"

  [ -d "$claude_dir" ] && for dst in "$claude_dir"/*; do
    [ -e "$dst" ] || [ -L "$dst" ] || continue
    base=$(basename "$dst")
    [ -n "${_DOT_GSTACK_SOURCE_CODEX_NAME_EXISTS[$base]+x}" ] && continue
    _dot_gstack_skill_dir_is_managed "$dst" || continue
    printf 'unexpected-target\tclaude/%s\t%s\n' "$base" "$dst"
  done

  while IFS= read -r dst; do
    base=$(basename "$dst")
    [ -n "${_DOT_GSTACK_SOURCE_CODEX_NAME_EXISTS[$base]+x}" ] && continue
    _dot_gstack_skill_dir_is_managed "$dst" || continue
    printf 'unexpected-target\tgenerated/%s\t%s\n' "$base" "$dst"
  done < <(_dot_gstack_each_prefixed_skill_target "$generated_dir")

  while IFS= read -r dst; do
    base=$(basename "$dst")
    [ -n "${_DOT_GSTACK_SOURCE_CODEX_NAME_EXISTS[$base]+x}" ] && continue
    _dot_gstack_skill_dir_is_managed "$dst" || continue
    printf 'unexpected-target\tcodex/%s\t%s\n' "$base" "$dst"
  done < <(_dot_gstack_each_prefixed_skill_target "$codex_dir")

  while IFS= read -r dst; do
    base=$(basename "$dst")
    [ -n "${_DOT_GSTACK_SOURCE_CODEX_NAME_EXISTS[$base]+x}" ] && continue
    _dot_gstack_skill_dir_is_managed "$dst" || continue
    printf 'unexpected-target\tgemini/%s\t%s\n' "$base" "$dst"
  done < <(_dot_gstack_each_prefixed_skill_target "$gemini_skill_dir")

  while IFS= read -r dst; do
    base=$(basename "$dst")
    [ -f "$opencode_generated_dir/$base/SKILL.md" ] && continue
    _dot_gstack_skill_dir_is_managed "$dst" || continue
    printf 'unexpected-target\topencode/%s\t%s\n' "$base" "$dst"
  done < <(_dot_gstack_each_prefixed_skill_target "$opencode_dir")
}

_dot_gstack_target_fingerprint() {
  local gstack_dir="$1"
  local claude_dir codex_dir gemini_ext gemini_skill_dir opencode_dir opencode_root
  local opencode_generated_dir
  local generated_dir
  local i name link_name asset rel skill_dir
  claude_dir="$(_dot_gstack_claude_skills_dir)"
  codex_dir="$(_dot_gstack_codex_skills_dir)"
  gemini_ext="$(_dot_gstack_gemini_extension_dir)"
  gemini_skill_dir="$(_dot_gstack_gemini_skills_dir)"
  opencode_dir="$(_dot_gstack_opencode_skills_dir)"
  opencode_root="$opencode_dir/gstack"
  opencode_generated_dir=$(_dot_gstack_opencode_generated_skills_dir)
  generated_dir=$(_dot_gstack_generated_skills_dir)

  {
    # Fingerprint the outputs too, not just the source checkout. Users can
    # install a new agent, remove generated skill files, or edit stale
    # dotfiles-managed directories between updates; a source-only cache would
    # miss those repairs and leave agents with broken registrations. Keep this
    # list driven by the source skill inventory rather than by scanning every
    # agent skill directory; unrelated user-installed skills can be numerous,
    # and the steady-state dot update path should not pay for them.
    printf 'version\t%s\n' "$_DOT_GSTACK_REGISTRATION_CACHE_VERSION"
    _dot_gstack_load_source_skills "$gstack_dir"

    _dot_gstack_emit_target_entry "$generated_dir" "generated"
    _dot_gstack_emit_target_entry "$generated_dir/GEMINI.md" "generated/GEMINI.md"
    _dot_gstack_emit_target_entry "$claude_dir/gstack" "claude/gstack"
    _dot_gstack_emit_target_entry "$claude_dir/connect-chrome" "claude/connect-chrome"
    for i in "${!_DOT_GSTACK_SOURCE_SKILL_NAMES[@]}"; do
      name="${_DOT_GSTACK_SOURCE_SKILL_NAMES[$i]}"
      link_name=$(_dot_gstack_codex_skill_name "$name")
      _dot_gstack_is_umbrella_link "$link_name" && continue
      _dot_gstack_emit_target_entry "$generated_dir/$link_name" "generated/$link_name"
      _dot_gstack_emit_target_entry "$(_dot_gstack_managed_marker "$generated_dir/$link_name")" \
        "generated/$link_name/.dotfiles-managed-gstack"
      _dot_gstack_emit_target_entry "$generated_dir/$link_name/SKILL.md" \
        "generated/$link_name/SKILL.md"
    done

    for i in "${!_DOT_GSTACK_SOURCE_SKILL_NAMES[@]}"; do
      name="${_DOT_GSTACK_SOURCE_SKILL_NAMES[$i]}"
      link_name=$(_dot_gstack_codex_skill_name "$name")
      _dot_gstack_is_umbrella_link "$link_name" && continue
      _dot_gstack_emit_target_entry "$claude_dir/$link_name" "claude/$link_name"
      _dot_gstack_emit_target_entry "$claude_dir/$link_name/SKILL.md" \
        "claude/$link_name/SKILL.md"
    done

    if _dot_gstack_has_agent codex; then
      _dot_gstack_emit_target_entry "$codex_dir/gstack" "codex/gstack"
      for i in "${!_DOT_GSTACK_SOURCE_SKILL_NAMES[@]}"; do
        name="${_DOT_GSTACK_SOURCE_SKILL_NAMES[$i]}"
        link_name=$(_dot_gstack_codex_skill_name "$name")
        _dot_gstack_is_umbrella_link "$link_name" && continue
        _dot_gstack_emit_target_entry "$codex_dir/$link_name" "codex/$link_name"
        _dot_gstack_emit_target_entry "$(_dot_gstack_managed_marker "$codex_dir/$link_name")" \
          "codex/$link_name/.dotfiles-managed-gstack"
        _dot_gstack_emit_target_entry "$codex_dir/$link_name/SKILL.md" "codex/$link_name/SKILL.md"
      done
    else
      _dot_gstack_emit_target_entry "$codex_dir/gstack" "codex/gstack"
    fi

    if _dot_gstack_has_agent gemini; then
      _dot_gstack_emit_target_entry "$gemini_ext" "gemini-extension"
      _dot_gstack_emit_target_entry "$(_dot_gstack_managed_marker "$gemini_ext")" \
        "gemini-extension/.dotfiles-managed-gstack"
      _dot_gstack_emit_target_entry "$gemini_ext/gemini-extension.json" \
        "gemini-extension/gemini-extension.json"
      _dot_gstack_emit_target_entry "$gemini_ext/GEMINI.md" "gemini-extension/GEMINI.md"
      for i in "${!_DOT_GSTACK_SOURCE_SKILL_NAMES[@]}"; do
        name="${_DOT_GSTACK_SOURCE_SKILL_NAMES[$i]}"
        link_name=$(_dot_gstack_codex_skill_name "$name")
        _dot_gstack_is_umbrella_link "$link_name" && continue
        _dot_gstack_emit_target_entry "$gemini_skill_dir/$link_name" "gemini/$link_name"
        _dot_gstack_emit_target_entry "$(_dot_gstack_managed_marker "$gemini_skill_dir/$link_name")" \
          "gemini/$link_name/.dotfiles-managed-gstack"
        _dot_gstack_emit_target_entry "$gemini_skill_dir/$link_name/SKILL.md" \
          "gemini/$link_name/SKILL.md"
      done
    else
      _dot_gstack_emit_target_entry "$gemini_ext" "gemini-extension"
    fi

    if _dot_gstack_has_agent opencode; then
      _dot_gstack_emit_target_entry "$opencode_generated_dir" "opencode-generated"
      _dot_gstack_emit_target_entry "$(_dot_gstack_managed_marker "$opencode_generated_dir")" \
        "opencode-generated/.dotfiles-managed-gstack"
      _dot_gstack_emit_target_entry "$opencode_generated_dir/gstack/SKILL.md" \
        "opencode-generated/gstack/SKILL.md"
      _dot_gstack_emit_target_entry "$opencode_root" "opencode/gstack"
      _dot_gstack_emit_target_entry "$(_dot_gstack_managed_marker "$opencode_root")" \
        "opencode/gstack/.dotfiles-managed-gstack"
      _dot_gstack_emit_target_entry "$opencode_root/SKILL.md" "opencode/gstack/SKILL.md"
      while IFS=$'\t' read -r asset rel; do
        [ -n "$asset" ] || continue
        _dot_gstack_emit_target_entry "$opencode_root/$rel" "opencode/gstack/$rel"
      done < <(_dot_gstack_each_opencode_runtime_asset "$gstack_dir")
      for skill_dir in "$opencode_generated_dir"/gstack-*/; do
        [ -f "$skill_dir/SKILL.md" ] || continue
        link_name=$(basename "$skill_dir")
        _dot_gstack_emit_target_entry "$skill_dir" "opencode-generated/$link_name"
        _dot_gstack_emit_target_entry "$(_dot_gstack_managed_marker "${skill_dir%/}")" \
          "opencode-generated/$link_name/.dotfiles-managed-gstack"
        _dot_gstack_emit_target_entry "$skill_dir/SKILL.md" \
          "opencode-generated/$link_name/SKILL.md"
        _dot_gstack_emit_target_entry "$opencode_dir/$link_name" "opencode/$link_name"
        _dot_gstack_emit_target_entry "$opencode_dir/$link_name/SKILL.md" \
          "opencode/$link_name/SKILL.md"
      done
    else
      _dot_gstack_emit_target_entry "$opencode_root" "opencode/gstack"
    fi

    _dot_gstack_emit_unexpected_managed_targets \
      "$gstack_dir" "$generated_dir" "$claude_dir" "$codex_dir" "$gemini_skill_dir" \
      "$opencode_dir"
  } 2>/dev/null | LC_ALL=C sort | _dot_gstack_hash_stream
}

_dot_gstack_cache_watch_entry_current() {
  local cache_file="$1" kind="$2" path="$3"

  case "$kind" in
    current)
      # The fast path is deliberately mtime based instead of content based.
      # Dot update's warm path runs often and users rarely need byte-level
      # validation when nothing in the generated registration tree has changed
      # since the last full pass. Any newer source, target, or parent directory
      # falls through to the existing fingerprint-and-repair path below, so this
      # only skips work for the steady state where the cache is unquestionably
      # fresher than every watched input and output.
      [ -e "$path" ] || [ -L "$path" ] || return 1
      [ ! "$path" -nt "$cache_file" ] || return 1
      ;;
    absent)
      [ ! -e "$path" ] && [ ! -L "$path" ] || return 1
      ;;
    *)
      return 1
      ;;
  esac
}

_dot_gstack_registration_watch_current() {
  local cache_file="$1" key first second version='' source='' target=''
  local saw_watch=0 cache_contents

  cache_contents=$(cat "$cache_file" 2>/dev/null) || return 1

  # A cache without watch entries came from an older registration strategy. It
  # may still be correct, but it cannot prove that no target was deleted after
  # the cache was written, so let the slower fingerprint path make that call and
  # rewrite the cache in the newer format.
  while IFS=$'\t' read -r key first second; do
    case "$key" in
      version)
        version="$first"
        ;;
      source)
        source="$first"
        ;;
      target)
        target="$first"
        ;;
      agent)
        [ "$second" = "$(_dot_gstack_agent_state "$first")" ] || return 1
        ;;
      watch)
        saw_watch=1
        _dot_gstack_cache_watch_entry_current "$cache_file" "$first" "$second" || return 1
        ;;
    esac
  done <<<"$cache_contents"

  [ "$version" = "$_DOT_GSTACK_REGISTRATION_CACHE_VERSION" ] || return 1
  [ -n "$source" ] && [ -n "$target" ] || return 1
  [ "$saw_watch" -eq 1 ] || return 1
}

_dot_gstack_emit_watch_entry() {
  local path="$1"
  if [ -e "$path" ] || [ -L "$path" ]; then
    printf 'watch\tcurrent\t%s\n' "$path"
  else
    printf 'watch\tabsent\t%s\n' "$path"
  fi
}

_dot_gstack_emit_source_watch_entries() {
  local gstack_dir="$1" asset skill_dir base

  # Watch both the root and each top-level source directory. The root catches
  # added/removed skills or runtime assets; per-directory watches catch a
  # SKILL.md being added under an already-existing directory, which would not
  # necessarily update the checkout root mtime.
  _dot_gstack_emit_watch_entry "$gstack_dir"
  for asset in SKILL.md bin browse review qa ETHOS.md; do
    _dot_gstack_emit_watch_entry "$gstack_dir/$asset"
  done

  for skill_dir in "$gstack_dir"/*/; do
    [ -d "$skill_dir" ] || continue
    base=$(basename "$skill_dir")
    _dot_gstack_skill_dir_is_skipped "$base" && continue
    skill_dir="${skill_dir%/}"
    _dot_gstack_emit_watch_entry "$skill_dir"
    _dot_gstack_emit_watch_entry "$skill_dir/SKILL.md"
  done

  # Watch the exclude list itself: editing it changes which skills should be
  # registered without touching anything in the upstream checkout, so without
  # this the warm fast path would keep serving the pre-edit registration set.
  _dot_gstack_emit_watch_entry "$(_dot_gstack_skill_exclude_file)"
}

_dot_gstack_emit_target_watch_entries() {
  local gstack_dir="$1"
  local claude_dir codex_dir gemini_ext gemini_skill_dir opencode_dir opencode_root
  local opencode_generated_dir
  local generated_dir
  local i name link_name asset rel skill_dir
  claude_dir="$(_dot_gstack_claude_skills_dir)"
  codex_dir="$(_dot_gstack_codex_skills_dir)"
  gemini_ext="$(_dot_gstack_gemini_extension_dir)"
  gemini_skill_dir="$(_dot_gstack_gemini_skills_dir)"
  opencode_dir="$(_dot_gstack_opencode_skills_dir)"
  opencode_root="$opencode_dir/gstack"
  opencode_generated_dir=$(_dot_gstack_opencode_generated_skills_dir)
  generated_dir=$(_dot_gstack_generated_skills_dir)

  # Parent directories are part of the watch set because stale managed skills
  # are discovered by scanning immediate children. If a new managed stale entry
  # appears, or a generated entry is removed, the parent mtime invalidates the
  # fast path and the normal repair scan runs.
  _dot_gstack_emit_watch_entry "$claude_dir"
  _dot_gstack_emit_watch_entry "$codex_dir"
  _dot_gstack_emit_watch_entry "$gemini_ext"
  _dot_gstack_emit_watch_entry "$gemini_skill_dir"
  _dot_gstack_emit_watch_entry "$generated_dir"
  _dot_gstack_emit_watch_entry "$opencode_dir"
  _dot_gstack_emit_watch_entry "$opencode_generated_dir"

  _dot_gstack_load_source_skills "$gstack_dir"

  _dot_gstack_emit_watch_entry "$generated_dir/GEMINI.md"
  _dot_gstack_emit_watch_entry "$claude_dir/gstack"
  _dot_gstack_emit_watch_entry "$claude_dir/connect-chrome"
  for i in "${!_DOT_GSTACK_SOURCE_SKILL_NAMES[@]}"; do
    name="${_DOT_GSTACK_SOURCE_SKILL_NAMES[$i]}"
    link_name=$(_dot_gstack_codex_skill_name "$name")
    _dot_gstack_is_umbrella_link "$link_name" && continue
    _dot_gstack_emit_watch_entry "$generated_dir/$link_name"
    _dot_gstack_emit_watch_entry "$(_dot_gstack_managed_marker "$generated_dir/$link_name")"
    _dot_gstack_emit_watch_entry "$generated_dir/$link_name/SKILL.md"
  done

  for i in "${!_DOT_GSTACK_SOURCE_SKILL_NAMES[@]}"; do
    name="${_DOT_GSTACK_SOURCE_SKILL_NAMES[$i]}"
    link_name=$(_dot_gstack_codex_skill_name "$name")
    _dot_gstack_is_umbrella_link "$link_name" && continue
    _dot_gstack_emit_watch_entry "$claude_dir/$link_name"
    _dot_gstack_emit_watch_entry "$claude_dir/$link_name/SKILL.md"
  done

  _dot_gstack_emit_watch_entry "$codex_dir/gstack"
  for i in "${!_DOT_GSTACK_SOURCE_SKILL_NAMES[@]}"; do
    name="${_DOT_GSTACK_SOURCE_SKILL_NAMES[$i]}"
    link_name=$(_dot_gstack_codex_skill_name "$name")
    _dot_gstack_is_umbrella_link "$link_name" && continue
    _dot_gstack_emit_watch_entry "$codex_dir/$link_name"
    _dot_gstack_emit_watch_entry "$(_dot_gstack_managed_marker "$codex_dir/$link_name")"
    _dot_gstack_emit_watch_entry "$codex_dir/$link_name/SKILL.md"
  done

  _dot_gstack_emit_watch_entry "$gemini_ext"
  _dot_gstack_emit_watch_entry "$(_dot_gstack_managed_marker "$gemini_ext")"
  _dot_gstack_emit_watch_entry "$gemini_ext/gemini-extension.json"
  _dot_gstack_emit_watch_entry "$gemini_ext/GEMINI.md"
  for i in "${!_DOT_GSTACK_SOURCE_SKILL_NAMES[@]}"; do
    name="${_DOT_GSTACK_SOURCE_SKILL_NAMES[$i]}"
    link_name=$(_dot_gstack_codex_skill_name "$name")
    _dot_gstack_is_umbrella_link "$link_name" && continue
    _dot_gstack_emit_watch_entry "$gemini_skill_dir/$link_name"
    _dot_gstack_emit_watch_entry "$(_dot_gstack_managed_marker "$gemini_skill_dir/$link_name")"
    _dot_gstack_emit_watch_entry "$gemini_skill_dir/$link_name/SKILL.md"
  done

  _dot_gstack_emit_watch_entry "$opencode_root"
  _dot_gstack_emit_watch_entry "$(_dot_gstack_managed_marker "$opencode_root")"
  _dot_gstack_emit_watch_entry "$opencode_root/SKILL.md"
  while IFS=$'\t' read -r asset rel; do
    [ -n "$asset" ] || continue
    _dot_gstack_emit_watch_entry "$opencode_root/$rel"
  done < <(_dot_gstack_each_opencode_runtime_asset "$gstack_dir")
  _dot_gstack_emit_watch_entry "$(_dot_gstack_managed_marker "$opencode_generated_dir")"
  _dot_gstack_emit_watch_entry "$opencode_generated_dir/gstack/SKILL.md"
  for skill_dir in "$opencode_generated_dir"/gstack-*/; do
    [ -f "$skill_dir/SKILL.md" ] || continue
    link_name=$(basename "$skill_dir")
    _dot_gstack_emit_watch_entry "${skill_dir%/}"
    _dot_gstack_emit_watch_entry "$(_dot_gstack_managed_marker "${skill_dir%/}")"
    _dot_gstack_emit_watch_entry "$skill_dir/SKILL.md"
    _dot_gstack_emit_watch_entry "$opencode_dir/$link_name"
    _dot_gstack_emit_watch_entry "$opencode_dir/$link_name/SKILL.md"
  done
}

_dot_gstack_emit_registration_watch_entries() {
  local gstack_dir="$1"

  printf 'agent\tclaude\t%s\n' "$(_dot_gstack_agent_state claude)"
  printf 'agent\tcodex\t%s\n' "$(_dot_gstack_agent_state codex)"
  printf 'agent\tgemini\t%s\n' "$(_dot_gstack_agent_state gemini)"
  printf 'agent\topencode\t%s\n' "$(_dot_gstack_agent_state opencode)"

  _dot_gstack_emit_source_watch_entries "$gstack_dir"
  _dot_gstack_emit_target_watch_entries "$gstack_dir"
}

_dot_gstack_registration_cache_current() {
  local gstack_dir="$1" cache_file source_fingerprint target_fingerprint
  local cached_source='' cached_target='' key value

  # A symlinked state directory means the old install shape still needs the
  # migration path. Never fast-path before that repair has run, because the
  # migration moves state out of the checkout and changes the durable cache
  # location from a gstack repo symlink to the real ~/.gstack directory.
  [ ! -L "$(_dot_gstack_state_dir)" ] || return 1

  cache_file=$(_dot_gstack_registration_cache_file)
  [ -f "$cache_file" ] || return 1

  if _dot_gstack_registration_watch_current "$cache_file"; then
    return 0
  fi

  while IFS=$'\t' read -r key value; do
    case "$key" in
      source) cached_source="$value" ;;
      target) cached_target="$value" ;;
    esac
  done <"$cache_file"

  [ -n "$cached_source" ] && [ -n "$cached_target" ] || return 1

  source_fingerprint=$(_dot_gstack_source_fingerprint "$gstack_dir")
  [ "$source_fingerprint" = "$cached_source" ] || return 1

  # Recompute target state after source matches. This is the expensive part we
  # are trying to avoid most of the time, but it is still much cheaper than
  # rewriting all generated Claude/Codex/Gemini registrations and it preserves
  # dot update's role as a repair command when generated files disappear.
  _DOT_GSTACK_TARGET_FRESHNESS_CACHE_FILE="$cache_file"
  target_fingerprint=$(_dot_gstack_target_fingerprint "$gstack_dir")
  _DOT_GSTACK_TARGET_FRESHNESS_CACHE_FILE=''
  [ "$target_fingerprint" = "$cached_target" ] || return 1
}

_dot_gstack_write_registration_cache() {
  local gstack_dir="$1" cache_file tmp
  cache_file=$(_dot_gstack_registration_cache_file)
  _dot_sibling_tmp_for "$cache_file" || return 1
  tmp="$REPLY"

  {
    printf 'version\t%s\n' "$_DOT_GSTACK_REGISTRATION_CACHE_VERSION"
    printf 'source\t%s\n' "$(_dot_gstack_source_fingerprint "$gstack_dir")"
    printf 'target\t%s\n' "$(_dot_gstack_target_fingerprint "$gstack_dir")"
    _dot_gstack_emit_registration_watch_entries "$gstack_dir"
  } >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  mv "$tmp" "$cache_file" || {
    rm -f "$tmp"
    return 1
  }
}
