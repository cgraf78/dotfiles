# shellcheck shell=bash
# Overlay link and skip-worktree management.
#
# Overlays intentionally shadow selected base-dotfiles paths with symlinks from
# `.dotfiles-<name>/home`. The base repo must mark those tracked paths
# skip-worktree while the overlay owns them, then restore the tracked version
# before pulling so Git never tries to merge through a symlink.

_overlay_link_target() {
  local rel="$1" name="$2" rest prefix=""
  rest="$rel"
  while [[ "$rest" == */* ]]; do
    rest="${rest#*/}"
    prefix="../$prefix"
  done
  REPLY="${prefix}.dotfiles-$name/home/$rel"
}

_overlay_link_matches() {
  local rel="$1" name="$2" target
  [[ -n "$name" ]] || return 1
  _overlay_link_target "$rel" "$name"
  target="$REPLY"
  [[ -L "$HOME/$rel" && "$(readlink "$HOME/$rel")" == "$target" ]]
}

# Check active providers independently of the generated manifest. This lets a
# missing manifest recover a live link without treating an arbitrary path as
# overlay-owned.
_overlay_active_provides() {
  local rel="$1" entry name path
  for entry in "${OVERLAYS[@]+"${OVERLAYS[@]}"}"; do
    IFS='|' read -r name path _ <<<"$entry"
    if [[ -f "$path/home/$rel" || -L "$path/home/$rel" ]]; then
      return 0
    fi
  done
  return 1
}

_overlay_active_link_matches() {
  local rel="$1" entry name path
  for entry in "${OVERLAYS[@]+"${OVERLAYS[@]}"}"; do
    IFS='|' read -r name path _ <<<"$entry"
    if [[ (-f "$path/home/$rel" || -L "$path/home/$rel") ]] &&
      _overlay_link_matches "$rel" "$name"; then
      return 0
    fi
  done
  return 1
}

_overlay_skip_worktree() {
  local entry
  entry=$($GIT ls-files -v -- "$1" 2>/dev/null) || true
  [[ "${entry:0:2}" == "S " ]]
}

# A tracked regular file is safe to shadow only when it is visible to Git and
# unchanged from the index. A remaining skip-worktree bit is owned by the user
# unless unstash just proved and restored the managed symlink.
_overlay_tracked_path_clean() {
  local rel="$1"
  _overlay_skip_worktree "$rel" && return 1
  $GIT diff --quiet -- "$rel" 2>/dev/null
}

# The deterministic pending path is discoverable after an unclean exit. Random
# build temps are never authority because a later process cannot find them.
_overlay_pending_manifest_path() {
  REPLY="${DOT_OVERLAY_MANIFEST}.pending"
}

_overlay_private_regular_file() {
  local path="$1" mode links
  [[ -f "$path" && ! -L "$path" && -O "$path" ]] || return 1
  mode=$(stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path" 2>/dev/null) || return 1
  links=$(stat -c '%h' "$path" 2>/dev/null || stat -f '%l' "$path" 2>/dev/null) || return 1
  [[ "$mode" != *[!0-7]* && "$links" == "1" ]] || return 1
  (((8#$mode & 077) == 0))
}

_overlay_file_identity() {
  local path="$1"
  REPLY=$(stat -c '%d:%i' "$path" 2>/dev/null || stat -f '%d:%i' "$path" 2>/dev/null) ||
    return 1
  [[ -n "$REPLY" ]]
}

_overlay_parse_manifest_record() {
  local line="$1" rel owner
  [[ "$line" == *$'\t'* ]] || return 1
  rel="${line%%$'\t'*}"
  owner="${line#*$'\t'}"
  [[ "$owner" != *$'\t'* ]] || return 1
  case "$rel" in
    "" | /* | . | .. | ./* | ../* | */./* | */../* | */. | */.. | */ | *//*)
      return 1
      ;;
  esac
  case "$owner" in
    "" | . | .. | */*) return 1 ;;
  esac
  REPLY_REL="$rel"
  REPLY_OWNER="$owner"
}

_overlay_pending_manifest_safe() {
  local path="$1" line REPLY_REL REPLY_OWNER
  _overlay_private_regular_file "$path" || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    _overlay_parse_manifest_record "$line" || return 1
  done <"$path"
}

# Selected, legacy, and write-ahead manifests may each describe a live link
# after a crash. Callers must accept their union and any recorded owner, while
# still validating the exact generated symlink before cleanup.
_overlay_authority_files() {
  local pending candidate existing duplicate
  _overlay_pending_manifest_path
  pending="$REPLY"
  if [[ -e "$DOT_OVERLAY_MANIFEST" || -L "$DOT_OVERLAY_MANIFEST" ]]; then
    if [[ ! -f "$DOT_OVERLAY_MANIFEST" || -L "$DOT_OVERLAY_MANIFEST" ]]; then
      REPLY="$DOT_OVERLAY_MANIFEST"
      return 1
    fi
  fi
  if [[ -e "$pending" || -L "$pending" ]]; then
    if ! _overlay_pending_manifest_safe "$pending"; then
      REPLY="$pending"
      return 1
    fi
  fi

  OVERLAY_AUTHORITY_MANIFESTS=()
  for candidate in "$DOT_OVERLAY_MANIFEST" "$DOT_OVERLAY_LEGACY_MANIFEST" "$pending"; do
    [[ -f "$candidate" && ! -L "$candidate" ]] || continue
    duplicate=0
    for existing in "${OVERLAY_AUTHORITY_MANIFESTS[@]+"${OVERLAY_AUTHORITY_MANIFESTS[@]}"}"; do
      if [[ "$existing" == "$candidate" ]]; then
        duplicate=1
        break
      fi
    done
    [[ "$duplicate" -eq 1 ]] || OVERLAY_AUTHORITY_MANIFESTS+=("$candidate")
  done
  REPLY="$pending"
}

# Populates the caller's dynamically scoped associative authority maps.
_overlay_load_authority() {
  local manifest line rel owner target REPLY_REL REPLY_OWNER
  _overlay_authority_files || return 1
  for manifest in "${OVERLAY_AUTHORITY_MANIFESTS[@]+"${OVERLAY_AUTHORITY_MANIFESTS[@]}"}"; do
    while IFS= read -r line || [[ -n "$line" ]]; do
      _overlay_parse_manifest_record "$line" || continue
      rel="$REPLY_REL"
      owner="$REPLY_OWNER"
      _overlay_path_is_authority "$rel" && continue
      _overlay_link_target "$rel" "$owner"
      target="$REPLY"
      _overlay_authority_paths["$rel"]=1
      _overlay_authority_targets["$rel"$'\t'"$target"]=1
    done <"$manifest"
  done
}

_overlay_authority_link_matches() {
  local rel="$1" dst="$HOME/$1" target
  [[ -L "$dst" ]] || return 1
  target=$(readlink "$dst") || return 1
  [[ -n "${_overlay_authority_targets["$rel"$'\t'"$target"]+x}" ]]
}

_overlay_path_is_authority() {
  local rel="$1" pending
  _overlay_pending_manifest_path
  pending="$REPLY"
  [[ "$HOME/$rel" == "$DOT_OVERLAY_MANIFEST" ||
    "$HOME/$rel" == "$DOT_OVERLAY_LEGACY_MANIFEST" ||
    "$HOME/$rel" == "$pending" ]]
}

_overlay_append_manifest_records() {
  local source="$1" destination="$2" line REPLY_REL REPLY_OWNER
  while IFS= read -r line || [[ -n "$line" ]]; do
    _overlay_parse_manifest_record "$line" || continue
    _overlay_path_is_authority "$REPLY_REL" && continue
    printf '%s\t%s\n' "$REPLY_REL" "$REPLY_OWNER" >>"$destination" || return 1
  done <"$source"
}

_overlay_append_candidates() {
  local destination="$1" name="$2" path="$3" inventory="$4"
  local overlay_home="$path/home" src rel rc=0 REPLY_REL REPLY_OWNER
  [[ -f "$inventory" && ! -L "$inventory" ]] || return 1
  while IFS= read -r -d '' src; do
    rel="${src#"$overlay_home"/}"
    _overlay_path_is_authority "$rel" && continue
    if ! _overlay_parse_manifest_record "$rel"$'\t'"$name" ||
      ! printf '%s\t%s\n' "$rel" "$name" >>"$destination"; then
      rc=1
      break
    fi
  done <"$inventory"
  return "$rc"
}

_overlay_prepare_inventories() {
  local root="$1" entry name path url inventory index=0
  for entry in "${OVERLAYS[@]+"${OVERLAYS[@]}"}"; do
    IFS='|' read -r name path url _ <<<"$entry"
    [[ -d "$path/home" ]] || continue
    _overlay_is_worktree "$path" || continue
    _overlay_checkout_matches "$path" "$url" || continue
    index=$((index + 1))
    inventory="$root/$index"
    : >"$inventory" || return 1
    chmod 600 "$inventory" || return 1
    find "$path/home" \( -type f -o -type l \) ! -name '*.~[0-9]*~' -print0 \
      >"$inventory" || return 1
    _overlay_inventory_files["$name"]="$inventory"
  done
}

# Publish old authority plus every exact link target this run may create before
# the first HOME or Git index mutation. The over-approximation is safe because
# cleanup still requires a live symlink to match a recorded generated target.
_overlay_publish_pending() {
  local pending build manifest entry name path inventory
  if ! _overlay_authority_files; then
    _warn "  warning: unsafe overlay recovery manifest; refusing to link: $REPLY"
    return 1
  fi
  pending="$REPLY"
  build=$(mktemp "${pending}.tmp.XXXXXX" 2>/dev/null) || {
    _warn "  warning: could not create overlay recovery manifest temp file: ${pending%/*}"
    return 1
  }
  if ! chmod 600 "$build"; then
    _warn "  warning: could not secure overlay recovery manifest temp file: $build"
    rm -f -- "$build"
    return 1
  fi

  for manifest in "${OVERLAY_AUTHORITY_MANIFESTS[@]+"${OVERLAY_AUTHORITY_MANIFESTS[@]}"}"; do
    if ! _overlay_append_manifest_records "$manifest" "$build"; then
      _warn "  warning: could not preserve overlay recovery authority: $manifest"
      rm -f -- "$build"
      return 1
    fi
  done
  for entry in "${OVERLAYS[@]+"${OVERLAYS[@]}"}"; do
    IFS='|' read -r name path _ <<<"$entry"
    inventory="${_overlay_inventory_files[$name]-}"
    [[ -n "$inventory" ]] || continue
    if ! _overlay_append_candidates "$build" "$name" "$path" "$inventory"; then
      _warn "  warning: could not inventory $name overlay recovery authority"
      rm -f -- "$build"
      return 1
    fi
  done

  if ! mv "$build" "$pending"; then
    _warn "  warning: could not publish overlay recovery manifest: $pending"
    rm -f -- "$build"
    return 1
  fi
  if ! _overlay_pending_manifest_safe "$pending"; then
    _warn "  warning: published overlay recovery manifest is unsafe: $pending"
    return 1
  fi
  REPLY="$pending"
}

_overlay_record_final() {
  local rel="$1" owner="$2"
  printf '%s\t%s\n' "$rel" "$owner" >>"$_overlay_manifest_new" || return 1
  _overlay_current_paths["$rel"]=1
}

# Restore only skip-worktree paths whose live symlink proves current overlay
# ownership. Other tools and users can set the same index bit, while the prior
# manifest can become stale, so neither signal alone authorizes a destructive
# checkout. _link_overlays re-symlinks owned paths after pull.
_overlay_restore_tracked_path() {
  local rel="$1"
  # shellcheck disable=SC2086  # $GIT is intentionally word-split (multi-word command).
  if ! $GIT update-index --no-skip-worktree "$rel" 2>/dev/null; then
    _warn "  warning: could not clear overlay index state: $rel"
    return 1
  fi
  # shellcheck disable=SC2086  # $GIT is intentionally word-split (multi-word command).
  if ! $GIT checkout -- "$rel" 2>/dev/null; then
    _warn "  warning: could not restore overlay base path: $rel"
    return 1
  fi
}

_unstash_overlay_overrides() {
  [[ -d "$DOTFILES" ]] || return 0

  local -A _overlay_authority_paths=()
  local -A _overlay_authority_targets=()
  local -a OVERLAY_AUTHORITY_MANIFESTS=()
  if ! _overlay_load_authority; then
    _warn "  warning: unsafe overlay recovery manifest; leaving overlay paths untouched: $REPLY"
    return 1
  fi

  local entry f owned
  while IFS= read -r -d '' entry; do
    [[ "${entry:0:2}" == "S " ]] || continue
    f="${entry:2}"
    owned=0

    if [[ -n "${_overlay_authority_paths[$f]+x}" ]]; then
      owned=1
      if _overlay_authority_link_matches "$f"; then
        _overlay_restore_tracked_path "$f" || return 1
        continue
      fi
    fi
    if _overlay_active_provides "$f"; then
      owned=1
    fi
    if _overlay_active_link_matches "$f"; then
      _overlay_restore_tracked_path "$f" || return 1
    elif [[ "$owned" -eq 1 ]]; then
      _warn "  warning: preserving replaced overlay path: $f"
    fi
  done < <($GIT ls-files -v -z 2>/dev/null)
}

# Link a single overlay's home/ directory into $HOME.
# Creates relative symlinks. Sets skip-worktree on base-repo files
# that overlay symlinks shadow.
# Appends linked paths to $_overlay_manifest_new (set by _link_overlays).
# Uses $_base_tracked (associative array) for O(1) tracked-file lookups.
_link_overlay() {
  local name="$1" path="$2" inventory="$3"
  local overlay_home="$path/home"
  [[ -d "$overlay_home" ]] || return 0
  [[ -f "$inventory" && ! -L "$inventory" ]] || return 1
  REPLY=""
  if [[ "${DOT_VERBOSE:-0}" -eq 1 ]]; then
    _ui_status running "$name overlay: linking"
  fi
  local linked=0
  local current=0
  while IFS= read -r -d '' src; do
    local rel="${src#"$overlay_home"/}"
    local dst="$HOME/$rel"
    if _overlay_path_is_authority "$rel"; then
      _warn "  skip (reserved overlay authority path): $rel"
      continue
    fi
    mkdir -p "$(dirname "$dst")" || return 1
    local target
    _overlay_link_target "$rel" "$name"
    target="$REPLY"
    if [[ -L "$dst" && "$(readlink "$dst")" == "$target" ]]; then
      if [[ -n "${_base_tracked[$rel]+x}" ]]; then
        $GIT update-index --skip-worktree "$rel" 2>/dev/null || return 1
      fi
      _overlay_record_final "$rel" "$name" || return 1
      current=$((current + 1))
      continue
    fi
    # Validate the destination before replacing it. A tracked regular file is
    # safe only when it is unchanged from the index; a symlink is safe only when
    # it is another active overlay's exact generated target. Everything else may
    # be user-owned state and must survive relinking.
    # Scope: this validates the leaf $dst only. A pre-existing symlinked PARENT
    # component (e.g. the user's own `$HOME/.config -> /elsewhere`) is honored,
    # not blocked — that is the user's intentional layout, and `find` never
    # descends an overlay-shipped symlinked dir, so an overlay cannot inject one.
    if [[ -L "$dst" ]]; then
      if [[ -n "${_base_tracked[$rel]+x}" ]] &&
        ! _overlay_active_link_matches "$rel"; then
        _warn "  skip (would replace unmanaged symlink): $rel"
        continue
      fi
    elif [[ -e "$dst" ]]; then
      if [[ -d "$dst" ]]; then
        _warn "  skip (directory in the way): $rel"
        continue
      fi
      if [[ -z "${_base_tracked[$rel]+x}" ]]; then
        _warn "  skip (would clobber untracked file): $rel"
        continue
      fi
      if ! _overlay_tracked_path_clean "$rel"; then
        _warn "  skip (would clobber modified tracked file): $rel"
        continue
      fi
    fi
    # `-n` (no-dereference): if $dst is a symlink to a directory, replace the
    # symlink itself instead of creating the new link *inside* that directory.
    ln -sfn "$target" "$dst" || return 1
    linked=$((linked + 1))
    if [[ -n "${_base_tracked[$rel]+x}" ]]; then
      $GIT update-index --skip-worktree "$rel" 2>/dev/null || return 1
      if [[ "${DOT_UI_TOTAL:-0}" -eq 0 || "${DOT_VERBOSE:-0}" -eq 1 ]]; then
        _log "  linked (override): $rel"
      fi
    else
      if [[ "${DOT_UI_TOTAL:-0}" -eq 0 || "${DOT_VERBOSE:-0}" -eq 1 ]]; then
        _log "  linked: $rel"
      fi
    fi
    _overlay_record_final "$rel" "$name" || return 1
  done <"$inventory"
  if [[ "$linked" -gt 0 ]]; then
    REPLY="$name overlay linked $linked"
    if [[ "${DOT_VERBOSE:-0}" -eq 1 ]]; then
      _ui_status changed "$REPLY"
    fi
  else
    REPLY="$name overlay current"
    if [[ "${DOT_VERBOSE:-0}" -eq 1 ]]; then
      _ui_status ok "$REPLY"
    fi
  fi
  return 0
}

# Link all active overlays and clean up stale symlinks from removed overlays.
_link_overlays() {
  local manifest="$DOT_OVERLAY_MANIFEST" pending
  if ! mkdir -p "${manifest%/*}"; then
    _warn "  warning: could not create overlay manifest directory: ${manifest%/*}"
    return 1
  fi
  if [[ (-e "$manifest" || -L "$manifest") &&
    (! -f "$manifest" || -L "$manifest") ]]; then
    _warn "  warning: overlay manifest path is not a regular file: $manifest"
    return 1
  fi

  local -A _overlay_authority_paths=()
  local -A _overlay_authority_targets=()
  local -A _overlay_current_paths=()
  local -A _overlay_inventory_files=()
  local -a OVERLAY_AUTHORITY_MANIFESTS=()
  if ! _overlay_load_authority; then
    _warn "  warning: unsafe overlay recovery manifest; refusing to link: $REPLY"
    return 1
  fi
  local adopted_legacy=0 authority
  if [[ "$DOT_OVERLAY_LEGACY_MANIFEST" != "$manifest" ]]; then
    for authority in "${OVERLAY_AUTHORITY_MANIFESTS[@]+"${OVERLAY_AUTHORITY_MANIFESTS[@]}"}"; do
      if [[ "$authority" == "$DOT_OVERLAY_LEGACY_MANIFEST" ]]; then
        adopted_legacy=1
        break
      fi
    done
  fi

  local _has_overlay_home=0
  local _overlay_total=0
  local _entry
  for _entry in "${OVERLAYS[@]+"${OVERLAYS[@]}"}"; do
    local _name _path _url
    IFS='|' read -r _name _path _url _ <<<"$_entry"
    if [[ -d "$_path/home" ]] && _overlay_checkout_matches "$_path" "$_url"; then
      _has_overlay_home=1
      _overlay_total=$((_overlay_total + 1))
    fi
  done
  if [[ "$_has_overlay_home" -eq 1 || "${DOT_UI_TOTAL:-0}" -gt 0 ]]; then
    if [[ "${DOT_UI_TOTAL:-0}" -gt 0 ]]; then
      _ui_stage_start "Overlays" "checking overlay links"
    else
      _ui_stage "Overlays"
    fi
    if [[ "$_has_overlay_home" -eq 0 && "${#OVERLAY_AUTHORITY_MANIFESTS[@]}" -eq 0 ]]; then
      [[ "${DOT_UI_TOTAL:-0}" -gt 0 ]] && _ui_stage_finish ok "0 overlays current"
      return 0
    fi
  fi

  # Replaces per-file $GIT ls-files --error-unmatch subprocesses.
  declare -A _base_tracked=()
  if [[ -d "$DOTFILES" ]]; then
    local _tf
    while IFS= read -r _tf; do
      _base_tracked["$_tf"]=1
    done < <($GIT ls-files 2>/dev/null)
  fi

  local _overlay_manifest_new inventory_root
  if ! _overlay_manifest_new=$(mktemp "${manifest}.tmp.XXXXXX" 2>/dev/null); then
    _warn "  warning: could not create overlay manifest temp file: ${manifest%/*}"
    return 1
  fi
  if ! chmod 600 "$_overlay_manifest_new"; then
    _warn "  warning: could not secure overlay manifest temp file: $_overlay_manifest_new"
    rm -f -- "$_overlay_manifest_new"
    return 1
  fi
  if ! inventory_root=$(mktemp -d "${manifest}.inventory.XXXXXX" 2>/dev/null) ||
    ! chmod 700 "$inventory_root" ||
    ! _overlay_prepare_inventories "$inventory_root"; then
    _warn "  warning: could not inventory overlay recovery candidates: ${manifest%/*}"
    rm -f -- "$_overlay_manifest_new"
    [[ -z "${inventory_root:-}" ]] || rm -rf -- "$inventory_root"
    return 1
  fi
  if ! _overlay_publish_pending; then
    rm -f -- "$_overlay_manifest_new"
    rm -rf -- "$inventory_root"
    return 1
  fi
  pending="$REPLY"

  # Reload after publication so stale cleanup accepts both prior owners and
  # every candidate target that may be left by an interrupted mutation phase.
  _overlay_authority_paths=()
  _overlay_authority_targets=()
  if ! _overlay_load_authority; then
    _warn "  warning: could not load published overlay recovery authority: $REPLY"
    rm -f -- "$_overlay_manifest_new"
    rm -rf -- "$inventory_root"
    return 1
  fi

  local entry
  local _overlay_done=0
  local _overlay_current=0
  local _overlay_changed=0
  local -a _overlay_changed_items=()
  for entry in "${OVERLAYS[@]+"${OVERLAYS[@]}"}"; do
    local name path url actual_origin expected_url
    IFS='|' read -r name path url _ <<<"$entry"
    [[ -d "$path/home" ]] || continue
    if ! _overlay_is_worktree "$path"; then
      _warn "  warning: $name overlay path exists but is not a Git worktree; leaving it untouched: $path"
      continue
    fi
    if ! _overlay_checkout_matches "$path" "$url"; then
      actual_origin="$REPLY"
      _overlay_effective_url "$url"
      expected_url="$REPLY"
      _overlay_origin_mismatch "$name" "$path" "$expected_url" "$actual_origin"
      continue
    fi
    _overlay_done=$((_overlay_done + 1))
    _dot_maybe_stage_progress "$name" "$_overlay_done" "$_overlay_total"
    local inventory="${_overlay_inventory_files[$name]-}"
    if [[ -z "$inventory" ]] || ! _link_overlay "$name" "$path" "$inventory"; then
      _warn "  warning: could not link $name overlay; recovery authority retained: $pending"
      rm -f -- "$_overlay_manifest_new"
      rm -rf -- "$inventory_root"
      return 1
    fi
    if [[ -n "${REPLY:-}" ]]; then
      if [[ "$REPLY" == *" linked "* ]]; then
        _overlay_changed=$((_overlay_changed + 1))
        _overlay_changed_items+=("$REPLY")
      else
        _overlay_current=$((_overlay_current + 1))
      fi
    fi
  done

  # Clean up every previously or provisionally authoritative path omitted from
  # the final manifest. Exact target validation prevents candidate
  # over-approximation from authorizing removal of user-owned paths.
  local rel dst stale_header=0
  for rel in "${!_overlay_authority_paths[@]}"; do
    [[ -z "${_overlay_current_paths[$rel]+x}" ]] || continue
    dst="$HOME/$rel"
    if [[ -L "$dst" ]]; then
      if ! _overlay_authority_link_matches "$rel"; then
        _warn "  skip (stale overlay link was replaced): $rel"
        continue
      fi
      if [[ "$stale_header" -eq 0 &&
        ("${DOT_UI_TOTAL:-0}" -eq 0 || "${DOT_VERBOSE:-0}" -eq 1) ]]; then
        _log_header "==> Cleaning stale overlay symlinks..."
        stale_header=1
      fi
      if ! rm -f -- "$dst"; then
        _warn "  warning: could not remove stale overlay link: $rel"
        rm -f -- "$_overlay_manifest_new"
        rm -rf -- "$inventory_root"
        return 1
      fi
      [[ "${DOT_UI_TOTAL:-0}" -eq 0 || "${DOT_VERBOSE:-0}" -eq 1 ]] && _log "  removed: $rel"
    elif [[ -e "$dst" ]]; then
      if [[ -z "${_base_tracked[$rel]+x}" ]] ||
        ! _overlay_tracked_path_clean "$rel"; then
        _warn "  skip (stale overlay path has local content): $rel"
      fi
      continue
    fi
    if [[ -n "${_base_tracked[$rel]+x}" ]]; then
      if ! $GIT update-index --no-skip-worktree "$rel" 2>/dev/null ||
        ! $GIT checkout -- "$rel" 2>/dev/null; then
        _warn "  warning: could not restore stale base path: $rel"
        rm -f -- "$_overlay_manifest_new"
        rm -rf -- "$inventory_root"
        return 1
      fi
    fi
  done

  # Commit final state before retiring either recovery authority. Checking the
  # inode closes portable mv's "destination became a directory" behavior and
  # proves the prepared file, rather than an intervening replacement, landed at
  # the selected path.
  local final_identity
  if ! _overlay_file_identity "$_overlay_manifest_new"; then
    _warn "  warning: could not identify prepared overlay manifest: $_overlay_manifest_new"
    rm -f -- "$_overlay_manifest_new"
    rm -rf -- "$inventory_root"
    return 1
  fi
  final_identity="$REPLY"
  if ! mv "$_overlay_manifest_new" "$manifest"; then
    _warn "  warning: could not write overlay manifest: $manifest"
    rm -f -- "$_overlay_manifest_new"
    rm -rf -- "$inventory_root"
    return 1
  fi
  if ! _overlay_private_regular_file "$manifest" ||
    ! _overlay_file_identity "$manifest" || [[ "$REPLY" != "$final_identity" ]]; then
    _warn "  warning: overlay manifest publication could not be verified: $manifest"
    rm -f -- "$_overlay_manifest_new"
    rm -rf -- "$inventory_root"
    return 1
  fi
  rm -rf -- "$inventory_root"
  if ! rm -f -- "$pending"; then
    _warn "  warning: could not remove overlay recovery manifest: $pending"
  fi
  if [[ "$adopted_legacy" -eq 1 ]]; then
    if [[ -f "$DOT_OVERLAY_LEGACY_MANIFEST" && ! -L "$DOT_OVERLAY_LEGACY_MANIFEST" ]]; then
      rm -f -- "$DOT_OVERLAY_LEGACY_MANIFEST" ||
        _warn "  warning: could not remove adopted overlay manifest: $DOT_OVERLAY_LEGACY_MANIFEST"
    else
      _warn "  warning: adopted overlay manifest changed type; leaving it untouched: $DOT_OVERLAY_LEGACY_MANIFEST"
    fi
  fi

  if [[ "${DOT_UI_TOTAL:-0}" -gt 0 ]]; then
    local _summary _status
    local _overlay_parts=()
    [[ "$_overlay_changed" -gt 0 ]] &&
      _overlay_parts+=("$(_ui_count_phrase "$_overlay_changed" overlay overlays) changed")
    [[ "$_overlay_current" -gt 0 || "$_overlay_changed" -eq 0 ]] &&
      _overlay_parts+=("$(_ui_count_phrase "$_overlay_current" overlay overlays) current")
    _summary=$(_join_comma "${_overlay_parts[@]}")
    _status=ok
    [[ "$_overlay_changed" -gt 0 ]] && _status=changed
    _ui_stage_finish "$_status" "$_summary"
    if [[ "${DOT_VERBOSE:-0}" -eq 0 ]]; then
      local _overlay_item
      for _overlay_item in "${_overlay_changed_items[@]+"${_overlay_changed_items[@]}"}"; do
        _ui_stage_note changed "$_overlay_item"
      done
    fi
  fi
}
