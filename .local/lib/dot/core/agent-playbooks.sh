# shellcheck shell=bash
# Discover trusted agent playbooks and render their human routing index.

if [[ -z "${DOT_OVERLAY_MANIFEST+x}" ]]; then
  # shellcheck source=constants.sh disable=SC1091
  . "${BASH_SOURCE[0]%/*}/constants.sh"
fi
if ! declare -F _overlay_authority_files >/dev/null 2>&1; then
  # shellcheck source=repos/overlays.sh disable=SC1091
  . "${BASH_SOURCE[0]%/*}/repos/overlays.sh"
fi

# Playbooks are user-authored agent policy, not an implementation detail of
# dot's merge runner. Keep their canonical path beside the always-loaded rules
# while this library retains dot-specific trust checks for overlay links.
_dot_playbook_root() {
  printf '%s\n' "$HOME/.config/agent-rules/playbooks.d"
}

_dot_playbook_below_root() {
  local file="$1" root_real="$2" parent_real
  parent_real=$(cd "${file%/*}" && pwd -P) || return 1
  case "$parent_real/" in
    "$root_real/"*) return 0 ;;
    *) return 1 ;;
  esac
}

# Base playbooks come from the current dotfiles index, not arbitrary HOME files.
_dot_playbook_base_files() {
  local rel file listing root root_real git_dir="$HOME/.dotfiles"
  root=$(_dot_playbook_root) || return 1
  root_real=$(cd "$root" && pwd -P) || return 1
  if [[ -d "$git_dir" ]]; then
    listing=$(
      git -c core.fsmonitor=false -c core.hooksPath=/dev/null \
        -C "$HOME" \
        --git-dir="$git_dir" --work-tree="$HOME" ls-files -- \
        ':(top,glob).config/agent-rules/playbooks.d/**/*.md'
    ) || return 1
  else
    listing=$(
      git -c core.fsmonitor=false -c core.hooksPath=/dev/null \
        -C "$HOME" ls-files -- \
        ':(top,glob).config/agent-rules/playbooks.d/**/*.md'
    ) || return 1
  fi
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    file="$HOME/$rel"
    [[ -f "$file" && ! -L "$file" ]] || return 1
    _dot_playbook_below_root "$file" "$root_real" || return 1
    printf '%s\n' "$file"
  done <<<"$listing"
}

# Overlay playbooks must be exact symlinks authorized by the overlay manifest.
_dot_playbook_overlay_tracked_load() {
  local owner="$1" repo="$HOME/.dotfiles-$1" listing tracked
  local -a pipeline_status=()

  # An overlay can contribute many playbooks, but Git's index is already the
  # complete trust authority for all of them. Inventory that narrow subtree
  # once per owner instead of starting one Git process for every manifest row.
  # Keep the command status visible: an invalid repository must still fail the
  # entire discovery rather than looking like an overlay with no playbooks.
  listing=$(
    git -c core.fsmonitor=false -c core.hooksPath=/dev/null \
      --git-dir="$repo/.git" --work-tree="$repo" \
      ls-files -z -- \
      ':(top,glob)home/.config/agent-rules/playbooks.d/**/*.md' |
      while IFS= read -r -d '' tracked; do
        # Overlay manifests cannot encode CR/LF path records. Ignore such Git
        # entries rather than converting them into ambiguous newline records.
        [[ "$tracked" != *$'\n'* && "$tracked" != *$'\r'* ]] || continue
        printf '%s\n' "${tracked#home/}"
      done
    pipeline_status=("${PIPESTATUS[@]}")
    [[ "${pipeline_status[0]:-1}" -eq 0 &&
      "${pipeline_status[1]:-1}" -eq 0 ]] || exit 2
  ) || return 2

  while IFS= read -r tracked; do
    [[ -n "$tracked" ]] || continue
    _dot_playbook_overlay_tracked_paths["$owner"$'\t'"$tracked"]=1
  done <<<"$listing"
  _dot_playbook_overlay_tracked_loaded["$owner"]=1
}

_dot_playbook_overlay_source_tracked() {
  local rel="$1" owner="$2"

  if [[ -z "${_dot_playbook_overlay_tracked_loaded[$owner]+x}" ]]; then
    _dot_playbook_overlay_tracked_load "$owner" || return 2
  fi
  [[ -n "${_dot_playbook_overlay_tracked_paths["$owner"$'\t'"$rel"]+x}" ]]
}

_dot_playbook_local_source_trusted() {
  local rel="$1" owner="$2" target="$3"
  local entry name path sync expected source root_real
  for entry in "${OVERLAYS[@]+"${OVERLAYS[@]}"}"; do
    IFS='|' read -r name path _ _ _ _ sync <<<"$entry"
    sync="${sync:-git}"
    [[ "$name" == "$owner" && "$sync" == "none" ]] || continue

    _overlay_record_link_target "$rel" "$name" "$path" "$sync" || return 2
    expected="$REPLY"
    [[ "$target" == "$expected" ]] || return 2
    source="$path/home/$rel"
    [[ -f "$source" && ! -L "$source" && -r "$source" ]] || return 2
    root_real=$(cd -P -- "$path/home" 2>/dev/null && pwd -P) || return 2
    _dot_playbook_below_root "$source" "$root_real" || return 2
    return 0
  done
  return 1
}

_dot_playbook_overlay_files() {
  local -a OVERLAY_AUTHORITY_MANIFESTS=()
  # Dynamically scoped into _dot_playbook_overlay_source_tracked so each
  # top-level discovery gets a fresh, invocation-local trust inventory.
  local -A _dot_playbook_overlay_tracked_loaded=()
  local -A _dot_playbook_overlay_tracked_paths=()
  local manifest line tracked_status local_status git_target
  local REPLY_REL REPLY_OWNER REPLY_TARGET

  _overlay_authority_files || return 1
  for manifest in "${OVERLAY_AUTHORITY_MANIFESTS[@]+"${OVERLAY_AUTHORITY_MANIFESTS[@]}"}"; do
    while IFS= read -r line || [[ -n "$line" ]]; do
      _overlay_parse_manifest_record "$line" || continue
      case "$REPLY_REL" in
        .config/agent-rules/playbooks.d/*.md)
          _overlay_link_matches "$REPLY_REL" "$REPLY_OWNER" "$REPLY_TARGET" || continue
          if _dot_playbook_local_source_trusted \
            "$REPLY_REL" "$REPLY_OWNER" "$REPLY_TARGET"; then
            local_status=0
          else
            local_status=$?
          fi
          if [[ "$local_status" -eq 0 ]]; then
            tracked_status=0
          elif [[ "$local_status" -eq 2 ]]; then
            return 1
          else
            _overlay_record_link_target "$REPLY_REL" "$REPLY_OWNER" \
              "$HOME/.dotfiles-$REPLY_OWNER" git || return 1
            git_target="$REPLY"
            if [[ "$REPLY_TARGET" != "$git_target" ]]; then
              tracked_status=1
            elif _dot_playbook_overlay_source_tracked "$REPLY_REL" "$REPLY_OWNER"; then
              tracked_status=0
            else
              tracked_status=$?
            fi
          fi
          [[ "$tracked_status" -eq 1 ]] && continue
          [[ "$tracked_status" -eq 0 ]] || return 1
          [[ -f "$HOME/$REPLY_REL" ]] || return 1
          printf '%s\n' "$HOME/$REPLY_REL"
          ;;
      esac
    done <"$manifest"
  done
}

_dot_playbook_files() {
  local listing
  listing=$(
    _dot_playbook_base_files || exit
    _dot_playbook_overlay_files || exit
  ) || return 1
  printf '%s\n' "$listing" | sed '/^$/d' | LC_ALL=C sort -u
}

# Return the one trigger declared in the contiguous metadata block at the top.
_dot_playbook_trigger() {
  local file="$1" line trigger="" count=0 title_seen=0 metadata_seen=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      "") continue ;;
      '# '*)
        if ((title_seen || metadata_seen)); then
          break
        fi
        title_seen=1
        ;;
      '<!-- agent-rule-id: '*' -->')
        metadata_seen=1
        ;;
      '<!-- agent-rule-trigger: '*' -->')
        metadata_seen=1
        trigger=${line#'<!-- agent-rule-trigger: '}
        trigger=${trigger%' -->'}
        [[ -n "$trigger" ]] || return 1
        count=$((count + 1))
        ;;
      *) break ;;
    esac
  done <"$file"

  [[ "$count" -eq 1 ]] || return 1
  printf '%s\n' "$trigger"
}

_dot_playbook_render_index() {
  local root="$1" file rel trigger
  shift

  for file in "$@"; do
    case "$file" in
      "$root"/*.md) ;;
      *) return 1 ;;
    esac
    rel=${file#"$root"/}
    case "$rel" in
      "" | /* | ./* | ../* | */../* | */.. | *'`'*) return 1 ;;
    esac
    trigger=$(_dot_playbook_trigger "$file") || return 1
    printf -- "- %s: \`%s\`\n" "$trigger" "$rel"
  done
}

_dot_playbook_index() {
  local root file listing
  local -a files=()

  root=$(_dot_playbook_root) || return 1
  listing=$(_dot_playbook_files) || return 1
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    files+=("$file")
  done <<<"$listing"
  ((${#files[@]} > 0)) || return 1
  _dot_playbook_render_index "$root" "${files[@]}"
}
