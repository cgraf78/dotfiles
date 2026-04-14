# shellcheck shell=bash
# Post-install hook for gstack.

post() {
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

uninstall() {
  # Remove per-skill symlinks that point into gstack
  local _link
  for _link in "$HOME/.claude/skills"/*/; do
    [[ -L "${_link%/}" ]] || continue
    local _target
    _target=$(readlink "${_link%/}")
    [[ "$_target" == gstack/* ]] && rm -f "${_link%/}"
  done
  rm -f "$HOME/.claude/skills/gstack"
}
