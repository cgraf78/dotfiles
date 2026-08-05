# shellcheck shell=bash
# dot doctor: Overlays checks.

_dr_check_overlays() {
  local conf_dir conf_count=0
  conf_dir="$(_overlay_conf_dir)"
  [[ -d "$conf_dir" ]] && conf_count=$(find "$conf_dir" -maxdepth 1 -name '*.conf' -type f 2>/dev/null | wc -l | tr -d ' ')
  _dr_section "Overlays ($conf_count configured)"

  if [[ "$conf_count" -eq 0 ]]; then
    _dr_skip "no overlays to check"
    return 0
  fi

  # Walk each conf, check against the parsed OVERLAYS array (filtered set).
  declare -A overlay_paths=()
  local f name want_url
  for f in "$conf_dir"/*.conf; do
    [[ -f "$f" ]] || continue
    name=$(_overlay_name "$f")
    # Extract URL from conf directly (OVERLAYS may have filtered it out).
    want_url=$(awk -F= '/^url=/ {sub(/^url=/, ""); print; exit}' "$f")

    # Is this overlay active for this host?
    local active=0 entry path _conf optional ssh_file
    for entry in "${OVERLAYS[@]+"${OVERLAYS[@]}"}"; do
      IFS='|' read -r n path _ _conf optional ssh_file <<<"$entry"
      if [[ "$n" == "$name" && "$_conf" == "$f" ]]; then
        active=1
        break
      fi
    done

    if [[ "$active" -eq 0 ]]; then
      _dr_skip "$name" "filtered out for this machine"
      continue
    fi
    overlay_paths["$name"]="$path"

    # Optional overlays are allowed to be unavailable on a machine. Required
    # overlays are not: a declared-but-missing deploy key means the machine
    # cannot satisfy the overlay contract and should be reported as unhealthy.
    if _overlay_key_missing "$ssh_file"; then
      if [[ "$optional" == "true" ]]; then
        _dr_skip "$name" "optional deploy key not present"
      else
        _dr_fail "$name: SSH deploy key missing" "$(_dr_tilde "$REPLY")"
      fi
      continue
    fi

    if [[ ! -d "$path/.git" ]]; then
      if [[ "$optional" == "true" ]]; then
        _dr_skip "$name" "optional overlay not cloned"
        continue
      fi
      _dr_fail "$name: not cloned" "expected at $(_dr_tilde "$path")"
      continue
    fi
    _dr_ok "$name: cloned" "$(_dr_tilde "$path")"

    # Origin URL matches conf
    local actual_url
    actual_url=$(git -C "$path" config --get remote.origin.url 2>/dev/null || echo "")
    if [[ "$actual_url" == "$want_url" ]]; then
      _dr_ok "$name: remote.origin.url matches conf"
    else
      _dr_warn "$name: remote URL drift" \
        "conf=$want_url vs actual=$actual_url"
    fi

    # Companion .ssh file: if present and the key is here (otherwise
    # we'd have skipped above), report it as present.
    local ssh_conf="${f%.conf}.ssh"
    if [[ -f "$ssh_conf" ]]; then
      local key
      key=$(awk '/^[[:space:]]+IdentityFile /{print $2; exit}' "$ssh_conf")
      if [[ -n "$key" ]]; then
        key="${key/#\~/$HOME}"
        _dr_ok "$name: SSH deploy key present" "$(_dr_tilde "$key")"
      fi
    fi
  done

  # Overlay symlinks — the manifest records which overlay owns each link.
  # Validate that links still resolve to that overlay, not merely to any
  # existing file, so stale/manual relinks are visible before hooks depend on
  # the wrong policy files.
  local manifest="$DOT_OVERLAY_MANIFEST"
  if [[ -f "$manifest" ]]; then
    declare -A manifest_owners=()
    # Keep the parser's dynamically scoped outputs local even though this call
    # uses it only as a validator and deliberately retains the raw values.
    # shellcheck disable=SC2034
    local issue_count=0 rel overlay_name REPLY_REL REPLY_OWNER
    local -a link_rels=() link_owners=() link_dsts=() link_targets=()
    while IFS=$'\t' read -r rel overlay_name _; do
      [[ -n "$rel" ]] || continue
      manifest_owners["$rel"]="$overlay_name"
    done <"$manifest"

    for rel in "${!manifest_owners[@]}"; do
      overlay_name="${manifest_owners[$rel]}"
      local dst="$HOME/$rel"

      if [[ ! -L "$dst" ]]; then
        ((issue_count++)) || true
        continue
      fi
      if [[ ! -e "$dst" ]]; then
        ((issue_count++)) || true
        continue
      fi
      if [[ -z "${overlay_name:-}" || -z "${overlay_paths[$overlay_name]+x}" ]]; then
        ((issue_count++)) || true
        continue
      fi

      link_rels+=("$rel")
      link_owners+=("$overlay_name")
      link_dsts+=("$dst")
    done

    local batch_ok=0 readlink_file="" readlink_output_count=0
    if [[ "${#link_dsts[@]}" -gt 0 ]] && _logfile_create; then
      readlink_file="$REPLY"
      if readlink "${link_dsts[@]}" >"$readlink_file" 2>/dev/null; then
        mapfile -t link_targets <"$readlink_file"
        readlink_output_count="${#link_targets[@]}"
        if [[ "$readlink_output_count" -eq "${#link_dsts[@]}" ]]; then
          batch_ok=1
        fi
      fi
      _dot_cleanup_remove_path "$readlink_file" || true
    fi

    local i actual expected_lexical expected
    for ((i = 0; i < ${#link_dsts[@]}; i++)); do
      rel="${link_rels[$i]}"
      overlay_name="${link_owners[$i]}"
      dst="${link_dsts[$i]}"
      actual=""
      if [[ "$batch_ok" -eq 1 ]]; then
        actual="${link_targets[$i]}"
      else
        actual=$(readlink "$dst" 2>/dev/null || true)
      fi

      # Managed links normally retain dot's deterministic relative target.
      # Check that cheap representation first; physical resolution remains the
      # compatibility fallback for equivalent absolute or hand-normalized links.
      if _overlay_parse_manifest_record "$rel"$'\t'"$overlay_name"; then
        _overlay_link_target "$rel" "$overlay_name"
        expected_lexical="$REPLY"
        [[ "$actual" == "$expected_lexical" ]] && continue
      fi

      expected="${overlay_paths[$overlay_name]}/home/$rel"
      if ! _dr_symlink_points_to "$dst" "$expected"; then
        ((issue_count++)) || true
      fi
    done
    if [[ "$issue_count" -eq 0 ]]; then
      _dr_ok "overlay symlinks healthy"
    else
      _dr_warn "$issue_count overlay symlink issue(s)" "run 'dot update' to re-link"
    fi
  fi
}
