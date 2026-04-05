#!/bin/bash
# Post-install hooks for dependencies.
# Convention: _post_<name> (dashes in dep name → underscores).
# Called by _run_post_hooks in helpers.sh after all deps are installed.
# Add new hooks here — no changes to helpers.sh needed.

_post_vimrc() {
  [[ -f "$HOME/.vim_runtime/install_awesome_vimrc.sh" ]] || return 0
  sh "$HOME/.vim_runtime/install_awesome_vimrc.sh" 2>/dev/null || \
    _warn "  warning: vimrc install script failed"
}

_post_gstack() {
  [[ -d "$HOME/.gstack" ]] || return 0
  mkdir -p "$HOME/.claude/skills"
  ln -sfn "$HOME/.gstack" "$HOME/.claude/skills/gstack"
  local _d
  for _d in "$HOME/.gstack"/*/; do
    if [[ -f "$_d/SKILL.md" && "$(basename "$_d")" != "node_modules" ]]; then
      ln -sfn "gstack/$(basename "$_d")" "$HOME/.claude/skills/$(basename "$_d")"
    fi
  done
}

_post_bash_preexec() {
  [[ -f "$HOME/.local/share/bash-preexec/bash-preexec.sh" ]] || return 0
  ln -sfn "$HOME/.local/share/bash-preexec/bash-preexec.sh" "$HOME/.bash-preexec.sh"
}
