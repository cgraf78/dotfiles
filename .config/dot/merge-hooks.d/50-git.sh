#!/bin/bash
# Configure git global settings.
# Idempotent — safe to run on every dot pull/update.

merge() {
  command -v git &>/dev/null || return 0

  echo "  Git"

  # Identity and editor
  git config --global user.name "Chris Graf"
  git config --global user.email "chris@grafhome.net"
  git config --global core.editor nvim

  # Delta pager (only if delta is installed)
  if command -v delta &>/dev/null; then
    git config --global core.pager delta
    git config --global interactive.diffFilter "delta --color-only"
    git config --global delta.navigate true
    git config --global delta.side-by-side false
    git config --global delta.line-numbers true
    git config --global delta.dark true
    git config --global delta.hyperlinks true
    git config --global diff.colorMoved default
  fi

  # Merge conflict style
  git config --global merge.conflictstyle zdiff3
}
