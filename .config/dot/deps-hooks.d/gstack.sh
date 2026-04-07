#!/bin/bash
# Post-install hook for gstack.

post_gstack() {
  [[ -d "$HOME/.local/share/gstack" ]] || return 0
  mkdir -p "$HOME/.claude/skills"
  ln -sfn "$HOME/.local/share/gstack" "$HOME/.claude/skills/gstack"
  local _d
  for _d in "$HOME/.local/share/gstack"/*/; do
    if [[ -f "$_d/SKILL.md" && "$(basename "$_d")" != "node_modules" ]]; then
      ln -sfn "gstack/$(basename "$_d")" "$HOME/.claude/skills/$(basename "$_d")"
    fi
  done
}
