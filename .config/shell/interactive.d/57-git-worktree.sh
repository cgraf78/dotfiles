# shellcheck shell=bash
# shellcheck disable=SC2154  # _fzf_pick set by 56-dot.sh
# Git worktree helpers: create, list, remove parallel working directories.
# Worktrees are stored under ~/worktrees/<repo>/<branch>.

_worktree_root() {
  local main_path
  main_path=$(git worktree list | head -1 | awk '{print $1}') || return 1
  echo "$HOME/worktrees/$(basename "$main_path")"
}

# Create or switch to a git worktree.
# Usage: gw <branch> [base]   -- create worktree (default base: HEAD)
#        gw                    -- list worktrees with fzf picker
gw() {
  _require_git_repo || return

  if [[ $# -eq 0 ]]; then
    gwl
    return
  fi

  local branch="$1"
  local base="${2:-HEAD}"
  local wt_root wt_path
  wt_root=$(_worktree_root) || return 1
  wt_path="$wt_root/${branch//\//__}"

  if [[ -d "$wt_path" ]]; then
    cd "$wt_path" || return
    echo "switched to existing worktree: $wt_path"
    return
  fi

  mkdir -p "$wt_root"

  if git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
    git worktree add "$wt_path" "$branch"
  else
    git worktree add -b "$branch" "$wt_path" "$base"
  fi || return

  cd "$wt_path" || return
  echo "created worktree: $wt_path"
}

# List worktrees with fzf picker; cd to selection.
gwl() {
  _require_git_repo || return

  local wt
  wt=$(
    git worktree list |
      fzf "${_fzf_pick[@]}" --prompt="worktree> " |
      awk '{print $1}'
  ) || return

  [[ -n "$wt" ]] || return
  cd "$wt" || return
}

# Remove a worktree by branch name or current worktree.
# Usage: gwd [branch]
gwd() {
  _require_git_repo || return

  local wt_root wt_path main_path
  wt_root=$(_worktree_root) || return 1
  main_path=$(git worktree list | head -1 | awk '{print $1}')

  if [[ $# -gt 0 ]]; then
    wt_path="$wt_root/${1//\//__}"
  else
    wt_path="$PWD"
  fi

  if [[ "$wt_path" == "$main_path" ]]; then
    echo "error: cannot remove the main worktree" >&2
    return 1
  fi

  if [[ "$PWD" == "$wt_path" || "$PWD" == "$wt_path/"* ]]; then
    cd "$main_path" || return
  fi

  git worktree remove "$wt_path" && echo "removed worktree: $wt_path"
}

# Prune stale worktrees and clean empty directories.
gwp() {
  _require_git_repo || return
  git worktree prune -v

  local wt_root
  wt_root=$(_worktree_root) 2>/dev/null || return 0
  [[ -d "$wt_root" ]] && find "$wt_root" -maxdepth 1 -type d -empty -delete 2>/dev/null
}
