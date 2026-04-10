#!/bin/bash
# Merge GitHub CLI preferences from dotfiles into the local gh config.
# Shared by dotbootstrap and dot (on pull).
# Requires yq.
#
# Policy: dotfiles keys overwrite matching local keys.
# Local-only keys are preserved.

_gh_yq() {
  local yq_bin=""
  yq_bin=$(command -v yq 2>/dev/null) || return 1
  "$yq_bin" --version 2>/dev/null | grep -qi 'mikefarah' || return 1
  printf '%s\n' "$yq_bin"
}

merge() {
  local src="$HOME/.config/dot/merge-hooks.d/gh-config.yml"
  local dst="$HOME/.config/gh/config.yml"
  local yq_bin=""

  [[ -f "$src" ]] || return 0

  yq_bin=$(_gh_yq) || return 0
  _log_dim "  GitHub CLI"

  # No existing config — just copy
  if [[ ! -f "$dst" ]]; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    return 0
  fi

  # Merge: source keys overwrite destination, local-only keys preserved
  local merged
  merged=$("$yq_bin" eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "$dst" "$src") || {
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
