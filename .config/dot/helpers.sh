#!/bin/bash
# Shared helpers for dot and dotbootstrap.

DOTFILES="$HOME/.dotfiles"
GIT="git --git-dir=$DOTFILES --work-tree=$HOME"
WORK_DIR="$HOME/.dotfiles-work"

# Pull work repo and re-run its bootstrap (symlinks, app config merges).
_pull_work_repo() {
  [[ -d "$WORK_DIR" ]] || return 0
  echo "==> Pulling work dotfiles..."
  git -C "$WORK_DIR" pull || echo "  warning: work dotfiles pull failed" >&2
  [[ -x "$WORK_DIR/bootstrap" ]] && "$WORK_DIR/bootstrap" || true
}

# Push work repo.
_push_work_repo() {
  [[ -d "$WORK_DIR" ]] || return 0
  echo "==> Pushing work dotfiles..."
  git -C "$WORK_DIR" push || echo "  warning: work dotfiles push failed" >&2
}

# Run all app config merge scripts (iTerm2, Karabiner, VS Code, etc.).
_run_merges() {
  for _script in "$HOME/.config/dot"/merge-*.sh; do
    [[ -f "$_script" ]] || continue
    . "$_script"
    _fn="merge_${_script##*merge-}"; _fn="${_fn%.sh}"
    "$_fn" || true
  done
}
