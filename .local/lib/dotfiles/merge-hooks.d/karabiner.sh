# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# shellcheck shell=bash
# Merge Karabiner-Elements profiles from dotfiles into the local config.
# Applied by standalone dot during initialization and update.
# macOS only — no-ops silently on other platforms.
# Requires jq.
#
# Policy: dotfiles profiles replace local profiles with the same name.
# Local-only profiles are preserved. Profile order is maintained.

_karabiner_profile_sources() {
  _karabiner_sources=()

  local source
  while IFS= read -r source; do
    _karabiner_sources+=("$source")
  done < <(dot_hook_family_files_matching karabiner/profiles.d '*.json' '*.replace/*.json')
}

_karabiner_build_source() {
  local dst="$1" tmp

  dot_sibling_tmp_for "$dst" || return 1
  tmp="$REPLY"

  if ! jq -s --indent 4 '{profiles: ([.[].profiles[]?])}' \
    "${_karabiner_sources[@]}" >"$tmp"; then
    dot_hook_warn "    warning: Karabiner source merge failed — skipping"
    rm -f "$tmp"
    return 1
  fi

  REPLY="$tmp"
}

# Main: merge dotfiles profiles into local Karabiner config.
merge() {
  _dot_tool_present karabiner || return 0
  [[ "$(uname)" == "Darwin" ]] || return 0

  dot_json_available || return 0

  local dst_dir="$HOME/.config/karabiner"
  local dst="$dst_dir/karabiner.json"
  local src="" tmp=""

  local -a _karabiner_sources
  _karabiner_profile_sources
  ((${#_karabiner_sources[@]} > 0)) || return 0
  [[ -d "$dst_dir" ]] || return 0

  dot_hook_log "  Karabiner"

  # No existing file — just copy
  if [[ ! -f "$dst" ]]; then
    if ((${#_karabiner_sources[@]} == 1)); then
      cp "${_karabiner_sources[0]}" "$dst"
      return 0
    fi
    _karabiner_build_source "$dst" || return 0
    dot_commit_tmp "$REPLY" "$dst"
    return 0
  fi

  _karabiner_build_source "$dst" || return 0
  src="$REPLY"

  # Merge: for each local profile, replace with dotfiles version if name matches.
  # Append any dotfiles profiles not already present locally.
  dot_sibling_tmp_for "$dst" || return 0
  tmp="$REPLY"
  if ! jq -n --indent 4 --slurpfile s "$src" --slurpfile d "$dst" '
    ($s[0].profiles | map({(.name): .}) | add) as $src_map |
    ($s[0].profiles | map(.name)) as $src_names |
    $d[0] | .profiles = (
      [.profiles[] |
        if .name as $n | $src_names | index($n) then $src_map[.name]
        else . end] +
      [$s[0].profiles[] |
        select(.name as $n | [$d[0].profiles[].name] | index($n) | not)]
    )
  ' >"$tmp"; then
    dot_hook_warn "    warning: Karabiner merge failed — skipping"
    rm -f "$src" "$tmp"
    return 0
  fi
  rm -f "$src"
  dot_commit_tmp "$tmp" "$dst"
}
