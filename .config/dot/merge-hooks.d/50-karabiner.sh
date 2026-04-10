#!/bin/bash
# Merge Karabiner-Elements profiles from dotfiles into the local config.
# Shared by dotbootstrap and dot (on pull).
# macOS only — no-ops silently on other platforms.
# Requires jq.
#
# Policy: dotfiles profiles replace local profiles with the same name.
# Local-only profiles are preserved. Profile order is maintained.

# Main: merge dotfiles profiles into local Karabiner config.
merge() {
  [[ "$(uname)" == "Darwin" ]] || return 0

  command -v jq &>/dev/null || return 0

  local src="$HOME/.config/dot/merge-hooks.d/karabiner.json"
  local dst_dir="$HOME/.config/karabiner"
  local dst="$dst_dir/karabiner.json"

  [[ -f "$src" ]] || return 0
  [[ -d "$dst_dir" ]] || return 0

  _log_dim "  Karabiner"

  # No existing file — just copy
  if [[ ! -f "$dst" ]]; then
    cp "$src" "$dst"
    return 0
  fi

  # Merge: for each local profile, replace with dotfiles version if name matches.
  # Append any dotfiles profiles not already present locally.
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
  ' > "$dst.tmp"; then
    _warn "    warning: Karabiner merge failed — skipping"
    rm -f "$dst.tmp"
    return
  fi
  mv "$dst.tmp" "$dst"
}
