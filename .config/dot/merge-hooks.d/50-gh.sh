#!/bin/bash
# Merge GitHub CLI preferences from dotfiles into the local gh config.
# Shared by dotbootstrap and dot (on pull).
# Requires yq.
#
# Policy: dotfiles keys overwrite matching local keys.
# Local-only keys are preserved.

merge() {
  local src="$HOME/.config/dot/merge-hooks.d/gh-config.yml"
  local dst="$HOME/.config/gh/config.yml"

  [[ -f "$src" ]] || return 0

  echo "  GitHub CLI"

  if ! command -v yq &>/dev/null; then
    echo "    skipped (yq not installed)"
    return 0
  fi

  # No existing config — just copy
  if [[ ! -f "$dst" ]]; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    return 0
  fi

  # Merge: source keys overwrite destination, local-only keys preserved
  local merged
  merged=$(yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "$dst" "$src") || {
    echo "    warning: merge failed — skipping"
    return 0
  }

  # Skip write if nothing changed
  if printf '%s\n' "$merged" | cmp -s - "$dst"; then
    return 0
  fi

  printf '%s\n' "$merged" > "$dst.tmp"
  mv "$dst.tmp" "$dst"
}
