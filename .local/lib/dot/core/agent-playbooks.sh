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

_dot_playbook_root() {
  printf '%s\n' "$HOME/.config/dot/agent-playbooks.d"
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
        ':(top,glob).config/dot/agent-playbooks.d/**/*.md'
    ) || return 1
  else
    listing=$(
      git -c core.fsmonitor=false -c core.hooksPath=/dev/null \
        -C "$HOME" ls-files -- \
        ':(top,glob).config/dot/agent-playbooks.d/**/*.md'
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
_dot_playbook_overlay_source_tracked() {
  local rel="$1" repo="$HOME/.dotfiles-$2" rc
  git -c core.fsmonitor=false -c core.hooksPath=/dev/null \
    --git-dir="$repo/.git" --work-tree="$repo" \
    ls-files --error-unmatch -- "home/$rel" >/dev/null 2>&1
  rc=$?
  case "$rc" in
    0) return 0 ;;
    1) return 1 ;;
    *) return 2 ;;
  esac
}

_dot_playbook_overlay_files() {
  local -a OVERLAY_AUTHORITY_MANIFESTS=()
  local manifest line tracked_status REPLY_REL REPLY_OWNER

  _overlay_authority_files || return 1
  for manifest in "${OVERLAY_AUTHORITY_MANIFESTS[@]+"${OVERLAY_AUTHORITY_MANIFESTS[@]}"}"; do
    while IFS= read -r line || [[ -n "$line" ]]; do
      _overlay_parse_manifest_record "$line" || continue
      case "$REPLY_REL" in
        .config/dot/agent-playbooks.d/*.md)
          _overlay_link_matches "$REPLY_REL" "$REPLY_OWNER" || continue
          if _dot_playbook_overlay_source_tracked "$REPLY_REL" "$REPLY_OWNER"; then
            tracked_status=0
          else
            tracked_status=$?
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
