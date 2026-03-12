#!/bin/bash
# Merge Karabiner-Elements profiles from dotfiles into the local config.
# Shared by dotbootstrap and dot (on pull).
# macOS only — no-ops silently on other platforms.
# Requires jq.
#
# Policy: dotfiles profiles replace local profiles with the same name.
# Local-only profiles are preserved. Profile order is maintained.

# Main: merge dotfiles profiles into local Karabiner config.
merge_karabiner() {
  [[ "$(uname)" == "Darwin" ]] || return 0

  echo "==> Merging Karabiner config..."

  if ! command -v jq &>/dev/null; then
    echo "  skipped (jq not installed)"
    return 0
  fi

  local src="$HOME/.config/dot/karabiner/karabiner.json"
  local dst_dir="$HOME/.config/karabiner"
  local dst="$dst_dir/karabiner.json"

  [[ -f "$src" ]] || return 0
  if [[ ! -d "$dst_dir" ]]; then
    echo "  skipped (config dir not found)"
    return 0
  fi

  # No existing file — just copy
  if [[ ! -f "$dst" ]]; then
    cp "$src" "$dst"
    return 0
  fi

  # Warn about profiles being overwritten
  local conflicts
  conflicts=$(jq -rn --slurpfile s "$src" --slurpfile d "$dst" '
    ($s[0].profiles | map(.name)) as $src_names |
    [$d[0].profiles[] | select(.name as $n | $src_names | index($n)) | .name] |
    if length > 0 then .[] | "    profile: \(.)" else empty end
  ' 2>/dev/null) || true
  if [[ -n "$conflicts" ]]; then
    echo "  overwriting local Karabiner profiles:"
    echo "$conflicts"
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
    echo "  warning: Karabiner merge failed — skipping"
    rm -f "$dst.tmp"
    return
  fi
  mv "$dst.tmp" "$dst"
}
